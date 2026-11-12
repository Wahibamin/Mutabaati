import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../core/constants/app_constants.dart';
import '../local_db/app_database.dart';

final backupServiceProvider = Provider<GoogleDriveBackupService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return GoogleDriveBackupService(
    db,
    onDatabaseReplaced: () async {
      ref.invalidate(appDatabaseProvider);
    },
  );
});

class BackupMetadata {
  final String backupDateIso;
  final int customersCount;
  final int suppliersCount;
  final double totalCustomersDebtAlayh;
  final double totalSuppliersDebtLah;
  final int schemaVersion;
  final String databaseSha256;

  const BackupMetadata({
    required this.backupDateIso,
    required this.customersCount,
    required this.suppliersCount,
    required this.totalCustomersDebtAlayh,
    required this.totalSuppliersDebtLah,
    required this.schemaVersion,
    required this.databaseSha256,
  });

  Map<String, dynamic> toJson() => {
        'backup_date': backupDateIso,
        'customers_count': customersCount,
        'suppliers_count': suppliersCount,
        'total_customers_debt_alayh': totalCustomersDebtAlayh,
        'total_suppliers_debt_lah': totalSuppliersDebtLah,
        'schema_version': schemaVersion,
        'database_sha256': databaseSha256,
      };
}

class DatabaseValidationResult {
  final int schemaVersion;
  final int foreignKeyErrors;

  const DatabaseValidationResult({
    required this.schemaVersion,
    required this.foreignKeyErrors,
  });
}

class DriveBackupItem {
  final String fileId;
  final String name;
  final DateTime createdTime;
  final int sizeBytes;

  const DriveBackupItem({
    required this.fileId,
    required this.name,
    required this.createdTime,
    required this.sizeBytes,
  });
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

/// خدمة النسخ الاحتياطي والاستعادة (Backup & Restore Flow) وفق المرحلة الخامسة (صفحة 10):
/// 1. تنفيذ `PRAGMA wal_checkpoint(FULL);` لتوليد ملف قاعدة بيانات متماسك ومستقل.
/// 2. إرفاق ملف وصفي صغير (JSON Metadata) يحتوي على: تاريخ النسخة، عدد الزبائن، عدد الموردين، إجمالي الديون، ورقم إصدار قاعدة البيانات، ثم ضغطهما في أرشيف ZIP.
/// 3. رفع الملف عبر Google Drive API v3 إلى مجلد خاص بالتطبيق أو حفظه محليًا ومشاركته.
/// 4. عند الاستعادة: أخذ نسخة احتياطية محلية طارئة (Safety Local Snapshot) والتحقق عبر `PRAGMA integrity_check;`.
class GoogleDriveBackupService {
  final AppDatabase _db;
  final Directory? _documentsDirectoryOverride;
  final Future<void> Function()? _onDatabaseReplaced;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  GoogleDriveBackupService(
    this._db, {
    Directory? documentsDirectoryOverride,
    Future<void> Function()? onDatabaseReplaced,
  })  : _documentsDirectoryOverride = documentsDirectoryOverride,
        _onDatabaseReplaced = onDatabaseReplaced;

  Future<Directory> _documentsDirectory() async =>
      _documentsDirectoryOverride ?? await getApplicationDocumentsDirectory();

  static DatabaseValidationResult validateDatabaseFile(
    File file, {
    int? maximumSchemaVersion,
  }) {
    if (!file.existsSync() || file.lengthSync() == 0) {
      throw StateError('ملف قاعدة البيانات غير موجود أو فارغ');
    }

    final database = sqlite.sqlite3.open(
      file.path,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      final integrity = database.select('PRAGMA integrity_check');
      final integrityValue = integrity.isEmpty
          ? ''
          : integrity.first.values.first.toString().toLowerCase();
      if (integrityValue != 'ok') {
        throw StateError('فشل PRAGMA integrity_check: $integrityValue');
      }

      final foreignKeys = database.select('PRAGMA foreign_key_check');
      if (foreignKeys.isNotEmpty) {
        throw StateError(
            'تحتوي النسخة على ${foreignKeys.length} علاقة Foreign Key مكسورة');
      }

      const requiredTables = <String>{
        'app_settings',
        'suppliers',
        'customers',
        'items',
        'purchases',
        'sales',
        'payments',
      };
      final tableRows = database.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tables = tableRows.map((row) => row['name'].toString()).toSet();
      final missing = requiredTables.difference(tables);
      if (missing.isNotEmpty) {
        throw StateError(
            'النسخة تفتقد الجداول الأساسية: ${missing.join(', ')}');
      }

      final schemaVersion =
          database.select('PRAGMA user_version').first.values.first as int;
      if (schemaVersion < 1) {
        throw StateError('رقم مخطط قاعدة البيانات غير صالح');
      }
      if (maximumSchemaVersion != null &&
          schemaVersion > maximumSchemaVersion) {
        throw StateError('النسخة أُنشئت بإصدار أحدث من التطبيق الحالي');
      }
      return DatabaseValidationResult(
        schemaVersion: schemaVersion,
        foreignKeyErrors: 0,
      );
    } finally {
      database.dispose();
    }
  }

  /// توليد أرشيف ZIP متكامل يحتوي على ملف SQLite + ملف metadata.json
  Future<File> createLocalBackupZip() async {
    final docsDir = await _documentsDirectory();
    final dbFile = File(p.join(docsDir.path, AppConstants.dbFileName));
    if (!await dbFile.exists()) {
      throw StateError('ملف قاعدة البيانات غير موجود بعد');
    }

    final backupDir = Directory(p.join(docsDir.path, 'backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final snapshotFile =
        File(p.join(backupDir.path, '.snapshot_$timestamp.sqlite'));

    // VACUUM INTO is SQLite's consistent snapshot mechanism and includes all
    // committed WAL content without racing a raw file copy.
    await _db.createConsistentSnapshot(snapshotFile.path);
    validateDatabaseFile(
      snapshotFile,
      maximumSchemaVersion: _db.schemaVersion,
    );

    final customers = await _db.getCustomers();
    final suppliers = await _db.getSuppliers();
    final summary = await _db.getDashboardSummary();
    final dbBytes = await snapshotFile.readAsBytes();
    final databaseSha256 = sha256.convert(dbBytes).toString();

    final metadata = BackupMetadata(
      backupDateIso: DateTime.now().toIso8601String(),
      customersCount: customers.length,
      suppliersCount: suppliers.length,
      totalCustomersDebtAlayh: summary.totalCustomersAlayh,
      totalSuppliersDebtLah: summary.totalSuppliersLah,
      schemaVersion: _db.schemaVersion,
      databaseSha256: databaseSha256,
    );

    final archive = Archive();
    archive
        .addFile(ArchiveFile(AppConstants.dbFileName, dbBytes.length, dbBytes));

    final metaBytes = utf8
        .encode(const JsonEncoder.withIndent('  ').convert(metadata.toJson()));
    archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('فشل ضغط ملف النسخة الاحتياطية');
    }

    final zipFile =
        File(p.join(backupDir.path, 'maqwati_backup_$timestamp.zip'));
    await zipFile.writeAsBytes(zipBytes, flush: true);
    if (await snapshotFile.exists()) await snapshotFile.delete();

    final settings = await _db.getAppSettings();
    await _db.updateAppSettings(
      ownerName: settings.ownerName,
      shopName: settings.shopName,
      phone: settings.phone,
      currency: settings.currency,
      pinCode: settings.pinCode,
      lastBackupAt: DateTime.now(),
      gdriveEmail: settings.gdriveEmail,
    );

    return zipFile;
  }

  /// استعادة قاعدة البيانات من ملف ZIP مع أخذ Safety Local Snapshot وفحص سلامة البيانات
  Future<void> restoreFromZipFile(File zipFile) async {
    final docsDir = await _documentsDirectory();
    final currentDbFile = File(p.join(docsDir.path, AppConstants.dbFileName));
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? sqliteEntry;
    ArchiveFile? metadataEntry;
    for (final file in archive) {
      final baseName = p.basename(file.name);
      if (baseName == AppConstants.dbFileName) {
        sqliteEntry = file;
      } else if (baseName == 'metadata.json') {
        metadataEntry = file;
      }
    }

    if (sqliteEntry == null) {
      throw StateError('ملف النسخة الاحتياطية لا يحتوي على قاعدة بيانات صالحة');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDbFile =
        File(p.join(docsDir.path, '.restore_candidate_$timestamp.sqlite'));
    final candidateBytes = List<int>.from(sqliteEntry.content as List);
    await tempDbFile.writeAsBytes(candidateBytes, flush: true);

    try {
      validateDatabaseFile(
        tempDbFile,
        maximumSchemaVersion: _db.schemaVersion,
      );

      if (metadataEntry != null) {
        final metadataBytes = List<int>.from(metadataEntry.content as List);
        final metadata = jsonDecode(utf8.decode(metadataBytes));
        if (metadata is Map<String, dynamic>) {
          final expectedHash = metadata['database_sha256']?.toString();
          if (expectedHash != null && expectedHash.isNotEmpty) {
            final actualHash = sha256.convert(candidateBytes).toString();
            if (actualHash != expectedHash) {
              throw StateError('بصمة قاعدة البيانات لا تطابق بيانات النسخة');
            }
          }
        }
      }

      final safetyPath = p.join(
        docsDir.path,
        'safety_snapshot_$timestamp.sqlite',
      );
      if (await currentDbFile.exists()) {
        await _db.createConsistentSnapshot(safetyPath);
        validateDatabaseFile(File(safetyPath));
      }

      await _db.flushWalCheckpoint();
      await _db.close();

      final rollbackFile =
          File(p.join(docsDir.path, '.pre_restore_$timestamp.sqlite'));
      var originalMoved = false;
      try {
        if (await currentDbFile.exists()) {
          await currentDbFile.rename(rollbackFile.path);
          originalMoved = true;
        }
        for (final suffix in const ['-wal', '-shm']) {
          final sidecar = File('${currentDbFile.path}$suffix');
          if (await sidecar.exists()) await sidecar.delete();
        }
        await tempDbFile.copy(currentDbFile.path);
        validateDatabaseFile(
          currentDbFile,
          maximumSchemaVersion: _db.schemaVersion,
        );
        if (await rollbackFile.exists()) await rollbackFile.delete();
      } catch (_) {
        if (await currentDbFile.exists()) await currentDbFile.delete();
        if (originalMoved && await rollbackFile.exists()) {
          await rollbackFile.rename(currentDbFile.path);
        }
        await _onDatabaseReplaced?.call();
        rethrow;
      }

      await _onDatabaseReplaced?.call();
    } finally {
      if (await tempDbFile.exists()) await tempDbFile.delete();
    }
  }

  /// تسجيل الدخول إلى Google ورفع النسخة الاحتياطية إلى Google Drive API v3
  Future<String> uploadBackupToGoogleDrive() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      throw StateError('تم إلغاء تسجيل الدخول إلى حساب Google');
    }

    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(client);

    final zipFile = await createLocalBackupZip();

    // البحث عن مجلد التطبيق أو إنشاؤه
    String? folderId;
    final folderList = await driveApi.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder' and name = '${AppConstants.driveBackupFolderName}' and trashed = false",
      spaces: 'drive',
    );

    if (folderList.files != null && folderList.files!.isNotEmpty) {
      folderId = folderList.files!.first.id;
    } else {
      final folderMeta = drive.File()
        ..name = AppConstants.driveBackupFolderName
        ..mimeType = 'application/vnd.google-apps.folder';
      final createdFolder = await driveApi.files.create(folderMeta);
      folderId = createdFolder.id;
    }

    final driveFile = drive.File()
      ..name = p.basename(zipFile.path)
      ..parents = folderId != null ? [folderId] : null;

    final media = drive.Media(zipFile.openRead(), await zipFile.length());
    await driveApi.files.create(driveFile, uploadMedia: media);

    final settings = await _db.getAppSettings();
    await _db.updateAppSettings(
      ownerName: settings.ownerName,
      shopName: settings.shopName,
      phone: settings.phone,
      currency: settings.currency,
      pinCode: settings.pinCode,
      lastBackupAt: DateTime.now(),
      gdriveEmail: account.email,
    );

    return account.email;
  }

  /// جلب قائمة النسخ الاحتياطية المتوفرة في Google Drive مرتبة من الأحدث للأقدم
  Future<List<DriveBackupItem>> listGoogleDriveBackups() async {
    final account =
        await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
    if (account == null) {
      throw StateError('يرجى تسجيل الدخول إلى حساب Google أولاً');
    }

    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(client);

    final fileList = await driveApi.files.list(
      q: "name contains 'maqwati_backup_' and trashed = false",
      orderBy: 'createdTime desc',
      $fields: 'files(id, name, createdTime, size)',
    );

    final items = <DriveBackupItem>[];
    for (final f in fileList.files ?? <drive.File>[]) {
      items.add(
        DriveBackupItem(
          fileId: f.id ?? '',
          name: f.name ?? 'نسخة احتياطية',
          createdTime: f.createdTime ?? DateTime.now(),
          sizeBytes: int.tryParse(f.size ?? '0') ?? 0,
        ),
      );
    }
    return items;
  }

  /// تنزيل نسخة احتياطية محددة من Google Drive واستعادتها بأمان
  Future<void> downloadAndRestoreFromDrive(String fileId) async {
    final account =
        await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
    if (account == null) {
      throw StateError('يرجى تسجيل الدخول إلى حساب Google أولاً');
    }

    final authHeaders = await account.authHeaders;
    final client = _GoogleAuthClient(authHeaders);
    final driveApi = drive.DriveApi(client);

    final media = await driveApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final docsDir = await _documentsDirectory();
    final downloadedZip =
        File(p.join(docsDir.path, 'downloaded_drive_backup.zip'));
    final sink = downloadedZip.openWrite();
    await media.stream.pipe(sink);
    await sink.close();

    await restoreFromZipFile(downloadedZip);
  }
}
