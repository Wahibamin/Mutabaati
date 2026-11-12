import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/models.dart';
import '../../domain/services/calculate_balance_service.dart';
import '../../domain/services/pin_security_service.dart';

/// مزود قاعدة البيانات الرئيسي في Riverpod
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// قاعدة البيانات المحلية (SQLite via Drift) وفق نموذج:
/// Immutable-style Ledger + Cached Balances (المرحلة الخامسة - صفحة 7-9).
/// ملاحظة هندسية مهمة:
/// تم بناء AppDatabase باستخدام Drift `customSelect` / `customInsert` / `customUpdate` و `transaction`
/// الأصيلة في مكتبة Drift بحيث يعمل المشروع فورًا في Android Studio بمجرد تشغيل `flutter pub get`
/// وبدون أن يتعطل المطور إذا لم يقم بتشغيل `build_runner`، مع دعم كامل للتدفقات اللحظية (Reactive Streams)
/// ومعاملات قاعدة البيانات الذرية (ACID Transactions) و MigrationStrategy.
class AppDatabase extends GeneratedDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// конструктор خاص لاختبارات الوحدة في الذاكرة (In-Memory SQLite Unit Testing)
  factory AppDatabase.forTesting(QueryExecutor executor) {
    return AppDatabase(executor);
  }

  // بث تغييرات الجداول لتحديث الواجهات لحظيًا بأقل من 100 مللي ثانية
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  Stream<void> get onDatabaseChanged => _changeController.stream;

  void notifyChanges() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await _createAllTablesAndIndexes();
          await _seedInitialData();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 1) {
            await _createAllTablesAndIndexes();
          }
          if (from < 2) {
            await _createAllTablesAndIndexes();
            await _migrateToV2();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _createAllTablesAndIndexes();
          await _migrateToV2();
          await _seedInitialDataIfNeeded();
        },
      );

  Future<void> _createAllTablesAndIndexes() async {
    // 1. جدول الإعدادات app_settings
    await customStatement('''
      CREATE TABLE IF NOT EXISTS app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        owner_name TEXT NOT NULL DEFAULT 'مقوت الخير',
        shop_name TEXT NOT NULL DEFAULT 'محل القات',
        phone TEXT NOT NULL DEFAULT '',
        currency TEXT NOT NULL DEFAULT 'ر.ي',
        pin_code TEXT NULL,
        last_backup_at INTEGER NULL,
        gdrive_email TEXT NULL
      )
    ''');

    // 2. جدول الموردين suppliers
    await customStatement('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NULL,
        notes TEXT NULL,
        balance_lah REAL NOT NULL DEFAULT 0,
        balance_alayh REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');

    // 3. جدول الزبائن customers
    await customStatement('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NULL,
        notes TEXT NULL,
        credit_limit REAL NULL,
        balance_alayh REAL NOT NULL DEFAULT 0,
        balance_lah REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)');

    // 4. جدول الأصناف items
    await customStatement('''
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        default_supplier_id INTEGER NULL REFERENCES suppliers(id),
        unit_name TEXT NOT NULL DEFAULT 'ربطة',
        current_qty REAL NOT NULL DEFAULT 0,
        last_buy_price REAL NOT NULL DEFAULT 0,
        average_cost REAL NOT NULL DEFAULT 0,
        cost_status TEXT NOT NULL DEFAULT 'FINAL' CHECK (cost_status IN ('FINAL', 'UNKNOWN')),
        default_sell_price REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 5. جدول فواتير الشراء purchases
    await customStatement('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL REFERENCES suppliers(id),
        item_id INTEGER NOT NULL REFERENCES items(id),
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_price REAL NOT NULL CHECK (unit_price >= 0),
        total_amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        remaining_amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        transfer_ref TEXT NULL,
        is_settled INTEGER NOT NULL DEFAULT 0,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // 6. جدول المبيعات والمرتجع sales
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES items(id),
        sale_type TEXT NOT NULL CHECK (sale_type IN ('CASH', 'CREDIT')),
        customer_id INTEGER NULL REFERENCES customers(id),
        quantity REAL NOT NULL CHECK (quantity > 0),
        unit_price REAL NOT NULL CHECK (unit_price >= 0),
        total_amount REAL NOT NULL,
        paid_amount REAL NOT NULL,
        remaining_amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        cogs_amount REAL NULL,
        cost_status TEXT NOT NULL DEFAULT 'UNKNOWN' CHECK (cost_status IN ('FINAL', 'PROVISIONAL', 'UNKNOWN')),
        provisional_quantity REAL NOT NULL DEFAULT 0,
        provisional_cost_amount REAL NOT NULL DEFAULT 0,
        returned_quantity REAL NOT NULL DEFAULT 0,
        returned_amount REAL NOT NULL DEFAULT 0,
        returned_cogs REAL NOT NULL DEFAULT 0,
        refunded_amount REAL NOT NULL DEFAULT 0,
        credit_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RETURNED')),
        returned_at INTEGER NULL,
        return_notes TEXT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 7. جدول سجل التالف wastage_records
    await customStatement('''
      CREATE TABLE IF NOT EXISTS wastage_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES items(id),
        quantity REAL NOT NULL CHECK (quantity > 0),
        estimated_cost REAL NOT NULL DEFAULT 0,
        cost_status TEXT NOT NULL DEFAULT 'UNKNOWN' CHECK (cost_status IN ('FINAL', 'UNKNOWN')),
        notes TEXT NOT NULL,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // 8. جدول السدادات payments
    await customStatement('''
      CREATE TABLE IF NOT EXISTS payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_type TEXT NOT NULL CHECK (party_type IN ('CUSTOMER', 'SUPPLIER')),
        party_id INTEGER NOT NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        method TEXT NOT NULL CHECK (method IN ('CASH', 'TRANSFER')),
        transfer_company TEXT NULL,
        transfer_number TEXT NULL,
        notes TEXT NULL,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payments_party ON payments(party_type, party_id)');

    // 9. جدول المصاريف expenses
    await customStatement('''
      CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_type TEXT NOT NULL CHECK (category_type IN ('WORK', 'PERSONAL')),
        title TEXT NOT NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        payment_method TEXT NOT NULL DEFAULT 'CASH',
        notes TEXT NULL,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_cat_date ON expenses(category_type, created_at)');

    // 10. تخصيص الدفعات الجديدة للفواتير مع إبقاء الدفعات التاريخية بلا روابط مزعومة.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS payment_allocations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payment_id INTEGER NOT NULL REFERENCES payments(id) ON DELETE CASCADE,
        document_type TEXT NOT NULL CHECK (document_type IN ('SALE', 'PURCHASE')),
        document_id INTEGER NOT NULL,
        amount REAL NOT NULL CHECK (amount > 0),
        created_at INTEGER NOT NULL,
        UNIQUE(payment_id, document_type, document_id)
      )
    ''');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payment_alloc_doc ON payment_allocations(document_type, document_id)');

    // 11. سجل مرتجعات مستقل يحافظ على الفاتورة الأصلية ويدعم الإرجاع الجزئي.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sale_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sales(id),
        quantity REAL NOT NULL CHECK (quantity > 0),
        amount REAL NOT NULL CHECK (amount >= 0),
        cogs_amount REAL NULL,
        cost_status TEXT NOT NULL DEFAULT 'UNKNOWN',
        refund_amount REAL NOT NULL DEFAULT 0 CHECK (refund_amount >= 0),
        refund_method TEXT NULL CHECK (refund_method IS NULL OR refund_method IN ('CASH', 'TRANSFER')),
        notes TEXT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 12. حركات الخزينة غير الربحية: رصيد افتتاحي، رأس مال، وتحويل داخلي.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS treasury_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_type TEXT NOT NULL CHECK (entry_type IN ('OPENING', 'CAPITAL', 'TRANSFER')),
        amount REAL NOT NULL CHECK (amount > 0),
        from_method TEXT NULL CHECK (from_method IS NULL OR from_method IN ('CASH', 'TRANSFER')),
        to_method TEXT NOT NULL CHECK (to_method IN ('CASH', 'TRANSFER')),
        notes TEXT NULL,
        is_reversed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // 13. مفاتيح طلب اختيارية تمنع تكرار الحفظ عند إعادة إرسال الطلب نفسه.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS operation_requests (
        operation_type TEXT NOT NULL,
        request_key TEXT NOT NULL,
        operation_id INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (operation_type, request_key)
      )
    ''');
  }

  Future<bool> _columnExists(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  Future<void> _addColumnIfMissing(
    String table,
    String column,
    String definition,
  ) async {
    if (!await _columnExists(table, column)) {
      await customStatement(
          'ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  /// Version 2 is additive only. Existing financial rows are never rewritten
  /// with invented costs or allocations; their cost status remains UNKNOWN.
  Future<void> _migrateToV2() async {
    await transaction(() async {
      await _addColumnIfMissing(
          'items', 'average_cost', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'items', 'cost_status', "TEXT NOT NULL DEFAULT 'UNKNOWN'");
      await _addColumnIfMissing('sales', 'cogs_amount', 'REAL NULL');
      await _addColumnIfMissing(
          'sales', 'cost_status', "TEXT NOT NULL DEFAULT 'UNKNOWN'");
      await _addColumnIfMissing(
          'sales', 'provisional_quantity', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'sales', 'provisional_cost_amount', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'sales', 'returned_quantity', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'sales', 'returned_amount', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'sales', 'returned_cogs', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'sales', 'refunded_amount', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'sales', 'credit_amount', 'REAL NOT NULL DEFAULT 0');
      await _addColumnIfMissing(
          'wastage_records', 'cost_status', "TEXT NOT NULL DEFAULT 'UNKNOWN'");
      await _createAllTablesAndIndexes();
      await _addColumnIfMissing(
          'sale_returns', 'cost_status', "TEXT NOT NULL DEFAULT 'UNKNOWN'");
    });
  }

  Future<void> _seedInitialDataIfNeeded() async {
    final rows = await customSelect('SELECT COUNT(*) AS cnt FROM app_settings')
        .getSingle();
    if (rows.read<int>('cnt') == 0) {
      await _seedInitialData();
    }
  }

  Future<void> _seedInitialData() async {
    await customInsert(
      'INSERT OR IGNORE INTO app_settings (id, owner_name, shop_name, phone, currency) VALUES (1, ?, ?, ?, ?)',
      variables: [
        const Variable<String>('أبو محمد المقوتي'),
        const Variable<String>('مقوت الخير للقات الفاخر'),
        const Variable<String>('777000000'),
        const Variable<String>('ر.ي'),
      ],
    );

    final existingItems =
        await customSelect('SELECT COUNT(*) AS cnt FROM items').getSingle();
    if (existingItems.read<int>('cnt') == 0) {
      for (final itemName in AppConstants.defaultQatItems) {
        await customInsert(
          "INSERT OR IGNORE INTO items (name, unit_name, current_qty, last_buy_price, average_cost, cost_status, default_sell_price, is_active) VALUES (?, ?, 0, 0, 0, 'FINAL', 5000, 1)",
          variables: [
            Variable<String>(itemName),
            const Variable<String>('ربطة'),
          ],
        );
      }
    }
  }

  // ===========================================================================
  // أولاً: إدارة الإعدادات وبيانات المستخدم (app_settings)
  // ===========================================================================
  Future<AppSettingsEntity> getAppSettings() async {
    await _seedInitialDataIfNeeded();
    final row = await customSelect('SELECT * FROM app_settings WHERE id = 1')
        .getSingle();
    final lastBackupMillis = row.readNullable<int>('last_backup_at');
    return AppSettingsEntity(
      id: row.read<int>('id'),
      ownerName: row.read<String>('owner_name'),
      shopName: row.read<String>('shop_name'),
      phone: row.read<String>('phone'),
      currency: row.read<String>('currency'),
      pinCode: row.readNullable<String>('pin_code'),
      lastBackupAt: lastBackupMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastBackupMillis)
          : null,
      gdriveEmail: row.readNullable<String>('gdrive_email'),
    );
  }

  Stream<AppSettingsEntity> watchAppSettings() async* {
    yield await getAppSettings();
    await for (final _ in onDatabaseChanged) {
      yield await getAppSettings();
    }
  }

  Future<void> updateAppSettings({
    required String ownerName,
    required String shopName,
    required String phone,
    required String currency,
    String? pinCode,
    DateTime? lastBackupAt,
    String? gdriveEmail,
  }) async {
    final storedPin = pinCode == null || pinCode.trim().isEmpty
        ? null
        : (PinSecurityService.isEncoded(pinCode)
            ? pinCode
            : PinSecurityService.encode(pinCode));
    await customUpdate(
      '''
      UPDATE app_settings
      SET owner_name = ?, shop_name = ?, phone = ?, currency = ?, pin_code = ?, last_backup_at = ?, gdrive_email = ?
      WHERE id = 1
      ''',
      variables: [
        Variable<String>(ownerName),
        Variable<String>(shopName),
        Variable<String>(phone),
        Variable<String>(currency),
        Variable<String>(storedPin),
        Variable<int>(lastBackupAt?.millisecondsSinceEpoch),
        Variable<String>(gdriveEmail),
      ],
    );
    notifyChanges();
  }

  /// Verifies both legacy plain-text PIN values and the salted PIN2 format.
  /// A successful legacy login upgrades the stored value in-place.
  Future<bool> verifyPin(String candidate) async {
    final settings = await getAppSettings();
    final stored = settings.pinCode;
    if (stored == null || stored.trim().isEmpty) return true;

    final verified = PinSecurityService.verify(candidate, stored);
    if (verified && !PinSecurityService.isEncoded(stored)) {
      await customUpdate(
        'UPDATE app_settings SET pin_code = ? WHERE id = 1',
        variables: [Variable<String>(PinSecurityService.encode(candidate))],
      );
      notifyChanges();
    }
    return verified;
  }

  // ===========================================================================
  // ثانيًا: إعادة بناء الأرصدة من دفتر الأستاذ الموحد (Immutable Ledger Recalculation)
  // ===========================================================================
  /// يعيد حساب رصيد الزبون («عليه» و«له») من جميع حركاته الفعلية داخل معاملة ذرية
  Future<({double balanceAlayh, double balanceLah})> recalculateCustomerBalance(
      int customerId) async {
    final salesRow = await customSelect(
      '''
      SELECT
        COALESCE(SUM(remaining_amount), 0.0) AS total_rem,
        COALESCE(SUM(credit_amount), 0.0) AS total_credit
      FROM sales
      WHERE customer_id = ? AND sale_type = 'CREDIT'
      ''',
      variables: [Variable<int>(customerId)],
    ).getSingle();

    final payRow = await customSelect(
      '''
      SELECT COALESCE(SUM(
        p.amount - COALESCE((
          SELECT SUM(a.amount) FROM payment_allocations a
          WHERE a.payment_id = p.id
        ), 0.0)
      ), 0.0) AS total_paid
      FROM payments p
      WHERE p.party_type = 'CUSTOMER' AND p.party_id = ? AND p.is_reversed = 0
      ''',
      variables: [Variable<int>(customerId)],
    ).getSingle();

    final totalRem = salesRow.read<double>('total_rem') -
        salesRow.read<double>('total_credit');
    final totalPaid = payRow.read<double>('total_paid');

    final result = CalculateBalanceService.computeCustomerBalance(
      totalActiveCreditRemaining: totalRem,
      totalPaymentsReceived: totalPaid,
    );

    await customUpdate(
      'UPDATE customers SET balance_alayh = ?, balance_lah = ? WHERE id = ?',
      variables: [
        Variable<double>(result.balanceAlayh),
        Variable<double>(result.balanceLah),
        Variable<int>(customerId),
      ],
    );

    return result;
  }

  /// يعيد حساب رصيد المورد («له» و«عليه») من جميع حركاته الفعلية داخل معاملة ذرية
  Future<({double balanceLah, double balanceAlayh})> recalculateSupplierBalance(
      int supplierId) async {
    final purchRow = await customSelect(
      '''
      SELECT COALESCE(SUM(remaining_amount), 0.0) AS total_rem
      FROM purchases
      WHERE supplier_id = ? AND is_reversed = 0
      ''',
      variables: [Variable<int>(supplierId)],
    ).getSingle();

    final payRow = await customSelect(
      '''
      SELECT COALESCE(SUM(
        p.amount - COALESCE((
          SELECT SUM(a.amount) FROM payment_allocations a
          WHERE a.payment_id = p.id
        ), 0.0)
      ), 0.0) AS total_paid
      FROM payments p
      WHERE p.party_type = 'SUPPLIER' AND p.party_id = ? AND p.is_reversed = 0
      ''',
      variables: [Variable<int>(supplierId)],
    ).getSingle();

    final totalRem = purchRow.read<double>('total_rem');
    final totalPaid = payRow.read<double>('total_paid');

    final result = CalculateBalanceService.computeSupplierBalance(
      totalPurchasesRemaining: totalRem,
      totalPaymentsPaid: totalPaid,
    );

    await customUpdate(
      'UPDATE suppliers SET balance_lah = ?, balance_alayh = ? WHERE id = ?',
      variables: [
        Variable<double>(result.balanceLah),
        Variable<double>(result.balanceAlayh),
        Variable<int>(supplierId),
      ],
    );

    return result;
  }

  // ===========================================================================
  // ثالثًا: إدارة الأصناف والمخزون (items)
  // ===========================================================================
  Future<List<ItemEntity>> getAllItems({bool activeOnly = true}) async {
    final whereClause = activeOnly ? 'WHERE i.is_active = 1' : '';
    final rows = await customSelect('''
      SELECT i.*, s.name AS supplier_name
      FROM items i
      LEFT JOIN suppliers s ON i.default_supplier_id = s.id
      $whereClause
      ORDER BY i.id ASC
    ''').get();

    return rows.map((r) {
      return ItemEntity(
        id: r.read<int>('id'),
        name: r.read<String>('name'),
        defaultSupplierId: r.readNullable<int>('default_supplier_id'),
        supplierName: r.readNullable<String>('supplier_name'),
        unitName: r.read<String>('unit_name'),
        currentQty: r.read<double>('current_qty'),
        lastBuyPrice: r.read<double>('last_buy_price'),
        averageCost: r.read<double>('average_cost'),
        costStatus: r.read<String>('cost_status'),
        defaultSellPrice: r.read<double>('default_sell_price'),
        isActive: r.read<int>('is_active') == 1,
      );
    }).toList();
  }

  Stream<List<ItemEntity>> watchAllItems({bool activeOnly = true}) async* {
    yield await getAllItems(activeOnly: activeOnly);
    await for (final _ in onDatabaseChanged) {
      yield await getAllItems(activeOnly: activeOnly);
    }
  }

  Future<int> addOrUpdateItem({
    int? id,
    required String name,
    int? defaultSupplierId,
    String unitName = 'ربطة',
    double defaultSellPrice = 0,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('اسم الصنف لا يمكن أن يكون فارغًا');
    }
    if (id == null) {
      final insertedId = await customInsert(
        '''
        INSERT INTO items (
          name, default_supplier_id, unit_name, current_qty, last_buy_price,
          average_cost, cost_status, default_sell_price, is_active
        ) VALUES (?, ?, ?, 0, 0, 0, 'FINAL', ?, 1)
        ''',
        variables: [
          Variable<String>(trimmed),
          Variable<int>(defaultSupplierId),
          Variable<String>(unitName),
          Variable<double>(defaultSellPrice),
        ],
      );
      notifyChanges();
      return insertedId;
    } else {
      await customUpdate(
        '''
        UPDATE items
        SET name = ?, default_supplier_id = ?, unit_name = ?, default_sell_price = ?
        WHERE id = ?
        ''',
        variables: [
          Variable<String>(trimmed),
          Variable<int>(defaultSupplierId),
          Variable<String>(unitName),
          Variable<double>(defaultSellPrice),
          Variable<int>(id),
        ],
      );
      notifyChanges();
      return id;
    }
  }

  // ===========================================================================
  // رابعًا: إدارة الموردين والشراء والسداد (suppliers & purchases)
  // ===========================================================================
  Future<List<SupplierEntity>> getSuppliers(
      {String? searchQuery, String filter = 'ALL'}) async {
    final rows = await customSelect('''
      SELECT * FROM suppliers
      WHERE is_active = 1
      ORDER BY balance_lah DESC, name ASC
    ''').get();

    var list = rows.map((r) {
      return SupplierEntity(
        id: r.read<int>('id'),
        name: r.read<String>('name'),
        phone: r.readNullable<String>('phone'),
        notes: r.readNullable<String>('notes'),
        balanceLah: r.read<double>('balance_lah'),
        balanceAlayh: r.read<double>('balance_alayh'),
        isActive: r.read<int>('is_active') == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
      );
    }).toList();

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list
          .where((s) =>
              s.name.toLowerCase().contains(q) || (s.phone ?? '').contains(q))
          .toList();
    }

    if (filter == 'SETTLED') {
      // تقرير «مصفر» (الرصيد = 0)
      list = list.where((s) => s.isSettled).toList();
    } else if (filter == 'HAS_BALANCE') {
      list = list.where((s) => !s.isSettled).toList();
    }

    return list;
  }

  Stream<List<SupplierEntity>> watchSuppliers() async* {
    yield await getSuppliers();
    await for (final _ in onDatabaseChanged) {
      yield await getSuppliers();
    }
  }

  Future<SupplierEntity?> getSupplierById(int id) async {
    final rows = await customSelect(
      'SELECT * FROM suppliers WHERE id = ?',
      variables: [Variable<int>(id)],
    ).get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SupplierEntity(
      id: r.read<int>('id'),
      name: r.read<String>('name'),
      phone: r.readNullable<String>('phone'),
      notes: r.readNullable<String>('notes'),
      balanceLah: r.read<double>('balance_lah'),
      balanceAlayh: r.read<double>('balance_alayh'),
      isActive: r.read<int>('is_active') == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
    );
  }

  Future<int> saveSupplier({
    int? id,
    required String name,
    String? phone,
    String? notes,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('يرجى إدخال اسم المورد');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id == null) {
      final newId = await customInsert(
        '''
        INSERT INTO suppliers (name, phone, notes, balance_lah, balance_alayh, is_active, created_at)
        VALUES (?, ?, ?, 0, 0, 1, ?)
        ''',
        variables: [
          Variable<String>(name.trim()),
          Variable<String>(phone?.trim()),
          Variable<String>(notes?.trim()),
          Variable<int>(now),
        ],
      );
      notifyChanges();
      return newId;
    } else {
      await customUpdate(
        'UPDATE suppliers SET name = ?, phone = ?, notes = ? WHERE id = ?',
        variables: [
          Variable<String>(name.trim()),
          Variable<String>(phone?.trim()),
          Variable<String>(notes?.trim()),
          Variable<int>(id),
        ],
      );
      notifyChanges();
      return id;
    }
  }

  Future<int?> _existingOperationId(
    String operationType,
    String? requestKey,
  ) async {
    if (requestKey == null || requestKey.trim().isEmpty) return null;
    final rows = await customSelect(
      '''
      SELECT operation_id FROM operation_requests
      WHERE operation_type = ? AND request_key = ?
      ''',
      variables: [
        Variable<String>(operationType),
        Variable<String>(requestKey.trim()),
      ],
    ).get();
    return rows.isEmpty ? null : rows.first.read<int>('operation_id');
  }

  Future<void> _rememberOperation(
    String operationType,
    String? requestKey,
    int operationId,
    int createdAt,
  ) async {
    if (requestKey == null || requestKey.trim().isEmpty) return;
    await customInsert(
      '''
      INSERT INTO operation_requests (
        operation_type, request_key, operation_id, created_at
      ) VALUES (?, ?, ?, ?)
      ''',
      variables: [
        Variable<String>(operationType),
        Variable<String>(requestKey.trim()),
        Variable<int>(operationId),
        Variable<int>(createdAt),
      ],
    );
  }

  Future<void> _settleProvisionalSaleCosts({
    required int itemId,
    required double quantity,
    required double actualUnitCost,
  }) async {
    var remaining = quantity;
    if (remaining <= 0) return;

    final rows = await customSelect(
      '''
      SELECT id, cogs_amount, provisional_quantity, provisional_cost_amount
      FROM sales
      WHERE item_id = ? AND provisional_quantity > 0
      ORDER BY created_at ASC, id ASC
      ''',
      variables: [Variable<int>(itemId)],
    ).get();

    for (final row in rows) {
      if (remaining <= 0.000001) break;
      final provisional = row.read<double>('provisional_quantity');
      final settled = provisional < remaining ? provisional : remaining;
      final oldCogs = row.readNullable<double>('cogs_amount') ?? 0.0;
      final oldProvisionalCost = row.read<double>('provisional_cost_amount');
      final oldProvisionalUnitCost =
          provisional > 0 ? oldProvisionalCost / provisional : 0.0;
      final newCogs =
          oldCogs + settled * (actualUnitCost - oldProvisionalUnitCost);
      final newProvisional = provisional - settled;
      final newProvisionalCost =
          oldProvisionalCost - settled * oldProvisionalUnitCost;
      await customUpdate(
        '''
        UPDATE sales
        SET cogs_amount = ?, provisional_quantity = ?, provisional_cost_amount = ?,
            cost_status = CASE WHEN ? <= 0.000001 THEN 'FINAL' ELSE 'PROVISIONAL' END
        WHERE id = ?
        ''',
        variables: [
          Variable<double>(newCogs),
          Variable<double>(newProvisional),
          Variable<double>(newProvisionalCost),
          Variable<double>(newProvisional),
          Variable<int>(row.read<int>('id')),
        ],
      );
      remaining -= settled;
    }
  }

  /// أ. عملية شراء بضاعة من مورد داخل معاملة ذرية (ACID Transaction - صفحة 6، TC-03)
  Future<int> recordSupplierPurchase({
    required int supplierId,
    required int itemId,
    required double quantity,
    required double unitPrice,
    required double paidAmount,
    String paymentMethod = 'CASH',
    String? transferRef,
    String? requestKey,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('يجب أن تكون الكمية أكبر من صفر');
    }
    if (unitPrice <= 0) {
      throw ArgumentError('يجب أن يكون سعر الشراء أكبر من صفر');
    }
    if (paidAmount < 0) {
      throw ArgumentError('المبلغ المدفوع لا يمكن أن يكون سالبًا');
    }

    return await transaction(() async {
      final existing = await _existingOperationId('PURCHASE', requestKey);
      if (existing != null) return existing;

      final totalAmount = quantity * unitPrice;
      if (paidAmount - totalAmount > 0.001) {
        throw ArgumentError(
            'المدفوع عند الشراء لا يمكن أن يتجاوز إجمالي الفاتورة');
      }
      final remainingAmount = totalAmount - paidAmount;
      final isSettled = remainingAmount.abs() <= 0.001;
      final now = DateTime.now().millisecondsSinceEpoch;

      final purchaseId = await customInsert(
        '''
        INSERT INTO purchases (
          supplier_id, item_id, quantity, unit_price, total_amount,
          paid_amount, remaining_amount, payment_method, transfer_ref,
          is_settled, is_reversed, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
        ''',
        variables: [
          Variable<int>(supplierId),
          Variable<int>(itemId),
          Variable<double>(quantity),
          Variable<double>(unitPrice),
          Variable<double>(totalAmount),
          Variable<double>(paidAmount),
          Variable<double>(remainingAmount),
          Variable<String>(paymentMethod),
          Variable<String>(transferRef),
          Variable<int>(isSettled ? 1 : 0),
          Variable<int>(now),
        ],
      );

      final itemRows = await customSelect(
        '''
        SELECT current_qty, average_cost, cost_status
        FROM items WHERE id = ?
        ''',
        variables: [Variable<int>(itemId)],
      ).get();
      if (itemRows.isEmpty) throw StateError('الصنف المحدد غير موجود');
      final item = itemRows.first;
      final oldQty = item.read<double>('current_qty');
      final oldAverage = item.read<double>('average_cost');
      final oldCostStatus = item.read<String>('cost_status');
      final negativeQty = oldQty < 0 ? -oldQty : 0.0;
      final shortageSettlement =
          quantity < negativeQty ? quantity : negativeQty;
      await _settleProvisionalSaleCosts(
        itemId: itemId,
        quantity: shortageSettlement,
        actualUnitCost: unitPrice,
      );

      final newQty = oldQty + quantity;
      double newAverage;
      String newCostStatus;
      if (oldQty > 0) {
        newAverage = ((oldQty * oldAverage) + (quantity * unitPrice)) / newQty;
        newCostStatus = oldCostStatus;
      } else {
        // A purchase first settles negative stock. Any positive remainder is
        // valued at this documented purchase price.
        newAverage = unitPrice;
        newCostStatus = 'FINAL';
      }

      await customUpdate(
        '''
        UPDATE items
        SET current_qty = ?, last_buy_price = ?, average_cost = ?,
            cost_status = ?,
            default_supplier_id = COALESCE(default_supplier_id, ?)
        WHERE id = ?
        ''',
        variables: [
          Variable<double>(newQty),
          Variable<double>(unitPrice),
          Variable<double>(newAverage),
          Variable<String>(newCostStatus),
          Variable<int>(supplierId),
          Variable<int>(itemId),
        ],
      );

      await _rememberOperation('PURCHASE', requestKey, purchaseId, now);

      // إعادة احتساب رصيد المورد («له» و«عليه»)
      await recalculateSupplierBalance(supplierId);

      notifyChanges();
      return purchaseId;
    });
  }

  Future<List<PurchaseEntity>> getPurchases(
      {int? supplierId, bool settledOnly = false}) async {
    final clauses = <String>['p.is_reversed = 0'];
    final vars = <Variable>[];
    if (supplierId != null) {
      clauses.add('p.supplier_id = ?');
      vars.add(Variable<int>(supplierId));
    }
    if (settledOnly) {
      clauses.add('p.is_settled = 1');
    }

    final whereSql = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = await customSelect(
      '''
      SELECT p.*, s.name AS supplier_name, i.name AS item_name
      FROM purchases p
      JOIN suppliers s ON p.supplier_id = s.id
      JOIN items i ON p.item_id = i.id
      $whereSql
      ORDER BY p.created_at DESC, p.id DESC
      ''',
      variables: vars,
    ).get();

    return rows.map((r) {
      return PurchaseEntity(
        id: r.read<int>('id'),
        supplierId: r.read<int>('supplier_id'),
        supplierName: r.read<String>('supplier_name'),
        itemId: r.read<int>('item_id'),
        itemName: r.read<String>('item_name'),
        quantity: r.read<double>('quantity'),
        unitPrice: r.read<double>('unit_price'),
        totalAmount: r.read<double>('total_amount'),
        paidAmount: r.read<double>('paid_amount'),
        remainingAmount: r.read<double>('remaining_amount'),
        paymentMethod: r.read<String>('payment_method'),
        transferRef: r.readNullable<String>('transfer_ref'),
        isSettled: r.read<int>('is_settled') == 1,
        isReversed: r.read<int>('is_reversed') == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
      );
    }).toList();
  }

  // ===========================================================================
  // خامسًا: إدارة الزبائن (customers)
  // ===========================================================================
  Future<List<CustomerEntity>> getCustomers({String? searchQuery}) async {
    final rows = await customSelect('''
      SELECT * FROM customers
      WHERE is_active = 1
      ORDER BY balance_alayh DESC, name ASC
    ''').get();

    var list = rows.map((r) {
      return CustomerEntity(
        id: r.read<int>('id'),
        name: r.read<String>('name'),
        phone: r.readNullable<String>('phone'),
        notes: r.readNullable<String>('notes'),
        creditLimit: r.readNullable<double>('credit_limit'),
        balanceAlayh: r.read<double>('balance_alayh'),
        balanceLah: r.read<double>('balance_lah'),
        isActive: r.read<int>('is_active') == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
      );
    }).toList();

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list
          .where((c) =>
              c.name.toLowerCase().contains(q) || (c.phone ?? '').contains(q))
          .toList();
    }

    return list;
  }

  Stream<List<CustomerEntity>> watchCustomers() async* {
    yield await getCustomers();
    await for (final _ in onDatabaseChanged) {
      yield await getCustomers();
    }
  }

  Future<CustomerEntity?> getCustomerById(int id) async {
    final rows = await customSelect(
      'SELECT * FROM customers WHERE id = ?',
      variables: [Variable<int>(id)],
    ).get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CustomerEntity(
      id: r.read<int>('id'),
      name: r.read<String>('name'),
      phone: r.readNullable<String>('phone'),
      notes: r.readNullable<String>('notes'),
      creditLimit: r.readNullable<double>('credit_limit'),
      balanceAlayh: r.read<double>('balance_alayh'),
      balanceLah: r.read<double>('balance_lah'),
      isActive: r.read<int>('is_active') == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
    );
  }

  Future<int> saveCustomer({
    int? id,
    required String name,
    String? phone,
    String? notes,
    double? creditLimit,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('يرجى إدخال اسم الزبون');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (id == null) {
      final newId = await customInsert(
        '''
        INSERT INTO customers (name, phone, notes, credit_limit, balance_alayh, balance_lah, is_active, created_at)
        VALUES (?, ?, ?, ?, 0, 0, 1, ?)
        ''',
        variables: [
          Variable<String>(name.trim()),
          Variable<String>(phone?.trim()),
          Variable<String>(notes?.trim()),
          Variable<double>(creditLimit),
          Variable<int>(now),
        ],
      );
      notifyChanges();
      return newId;
    } else {
      await customUpdate(
        'UPDATE customers SET name = ?, phone = ?, notes = ?, credit_limit = ? WHERE id = ?',
        variables: [
          Variable<String>(name.trim()),
          Variable<String>(phone?.trim()),
          Variable<String>(notes?.trim()),
          Variable<double>(creditLimit),
          Variable<int>(id),
        ],
      );
      notifyChanges();
      return id;
    }
  }

  // ===========================================================================
  // سادسًا: منظومة المبيعات والمرتجع والتالف (sales & wastage_records)
  // ===========================================================================
  /// ب. عملية بيع قات (نقد أو آجل أو دفع جزئي) داخل معاملة ذرية (صفحة 6، TC-01, TC-02, TC-08)
  Future<int> recordSale({
    required int itemId,
    required String saleType, // 'CASH' or 'CREDIT'
    int? customerId,
    required double quantity,
    required double unitPrice,
    double? paidAmount,
    String paymentMethod = 'CASH', // 'CASH' or 'TRANSFER'
    String? requestKey,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('يجب أن تكون الكمية المباعة أكبر من صفر');
    }
    if (unitPrice <= 0) {
      throw ArgumentError('يرجى إدخال سعر بيع صحيح أكبر من صفر');
    }
    if (saleType == 'CREDIT' && customerId == null) {
      throw ArgumentError('لا يُسمح بحفظ بيع «آجل» بدون تحديد الزبون');
    }

    return await transaction(() async {
      final existing = await _existingOperationId('SALE', requestKey);
      if (existing != null) return existing;

      final totalAmount = quantity * unitPrice;
      final actualPaid = saleType == 'CASH' ? totalAmount : (paidAmount ?? 0.0);
      if (actualPaid < 0) {
        throw ArgumentError('المبلغ المدفوع لا يمكن أن يكون سالبًا');
      }
      if (actualPaid - totalAmount > 0.001) {
        throw ArgumentError(
            'المبلغ المدفوع عند البيع لا يمكن أن يتجاوز إجمالي الفاتورة');
      }
      final remainingAmount =
          saleType == 'CASH' ? 0.0 : (totalAmount - actualPaid);
      final now = DateTime.now().millisecondsSinceEpoch;

      final itemRows = await customSelect(
        '''
        SELECT current_qty, average_cost, last_buy_price, cost_status
        FROM items WHERE id = ?
        ''',
        variables: [Variable<int>(itemId)],
      ).get();
      if (itemRows.isEmpty) throw StateError('الصنف المحدد غير موجود');
      final item = itemRows.first;
      final currentQty = item.read<double>('current_qty');
      final averageCost = item.read<double>('average_cost');
      final lastBuyPrice = item.read<double>('last_buy_price');
      final itemCostStatus = item.read<String>('cost_status');
      final finalQuantity = currentQty > 0
          ? (quantity < currentQty ? quantity : currentQty)
          : 0.0;
      final provisionalQuantity = quantity - finalQuantity;
      final provisionalUnitCost = lastBuyPrice > 0 ? lastBuyPrice : 0.0;
      final provisionalCostAmount = provisionalQuantity * provisionalUnitCost;
      final cogsAmount = finalQuantity * averageCost + provisionalCostAmount;
      final costStatus = itemCostStatus == 'UNKNOWN'
          ? 'UNKNOWN'
          : (provisionalQuantity > 0.000001 ? 'PROVISIONAL' : 'FINAL');

      final saleId = await customInsert(
        '''
        INSERT INTO sales (
          item_id, sale_type, customer_id, quantity, unit_price,
          total_amount, paid_amount, remaining_amount, payment_method,
          cogs_amount, cost_status, provisional_quantity,
          provisional_cost_amount, status, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE', ?)
        ''',
        variables: [
          Variable<int>(itemId),
          Variable<String>(saleType),
          Variable<int>(customerId),
          Variable<double>(quantity),
          Variable<double>(unitPrice),
          Variable<double>(totalAmount),
          Variable<double>(actualPaid),
          Variable<double>(remainingAmount),
          Variable<String>(paymentMethod),
          Variable<double>(cogsAmount),
          Variable<String>(costStatus),
          Variable<double>(provisionalQuantity),
          Variable<double>(provisionalCostAmount),
          Variable<int>(now),
        ],
      );

      // إنقاص الكمية المتاحة من الصنف (مع السماح بالبيع المباشر حتى لو لم يقيد البائع كمية الشراء مسبقًا - مرونة تشغيلية صفحة 2)
      await customUpdate(
        'UPDATE items SET current_qty = current_qty - ? WHERE id = ?',
        variables: [
          Variable<double>(quantity),
          Variable<int>(itemId),
        ],
      );

      // في حال البيع الآجل: تحديث رصيد الزبون «عليه»
      if (customerId != null) {
        await recalculateCustomerBalance(customerId);
      }

      await _rememberOperation('SALE', requestKey, saleId, now);

      notifyChanges();
      return saleId;
    });
  }

  /// ج. مرتجع مبيعات (اختر الحركة > تراجع عنها) داخل معاملة ذرية (صفحة 7، TC-06)
  Future<void> returnSale({
    required int saleId,
    String returnNotes = 'مرتجع مبيعات',
  }) async {
    final rows = await customSelect(
      '''
      SELECT quantity, returned_quantity, total_amount, paid_amount,
             refunded_amount, payment_method, sale_type, customer_id
      FROM sales WHERE id = ?
      ''',
      variables: [Variable<int>(saleId)],
    ).get();
    if (rows.isEmpty) throw StateError('عملية البيع غير موجودة');
    final sale = rows.first;
    final returnable =
        sale.read<double>('quantity') - sale.read<double>('returned_quantity');
    if (returnable <= 0.000001) {
      throw StateError('تم إرجاع هذه الحركة بالكامل مسبقًا');
    }
    final returnAmount = sale.read<double>('total_amount') *
        returnable /
        sale.read<double>('quantity');
    final refundablePaid =
        sale.read<double>('paid_amount') - sale.read<double>('refunded_amount');
    final refund = refundablePaid <= 0
        ? 0.0
        : (refundablePaid < returnAmount ? refundablePaid : returnAmount);

    await returnSalePartial(
      saleId: saleId,
      quantity: returnable,
      refundAmount: refund,
      refundMethod: refund > 0 ? sale.read<String>('payment_method') : null,
      returnNotes: returnNotes,
    );
  }

  /// Records a partial or full return without deleting the original invoice.
  /// Cash refund and customer credit are deliberately separate values.
  Future<int> returnSalePartial({
    required int saleId,
    required double quantity,
    double? refundAmount,
    String? refundMethod,
    String returnNotes = 'مرتجع مبيعات',
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('كمية المرتجع يجب أن تكون أكبر من صفر');
    }

    return transaction(() async {
      final rows = await customSelect(
        'SELECT * FROM sales WHERE id = ?',
        variables: [Variable<int>(saleId)],
      ).get();

      if (rows.isEmpty) throw StateError('عملية البيع غير موجودة');
      final sale = rows.first;
      final soldQuantity = sale.read<double>('quantity');
      final alreadyReturned = sale.read<double>('returned_quantity');
      final returnable = soldQuantity - alreadyReturned;
      if (quantity - returnable > 0.000001) {
        throw ArgumentError('كمية المرتجع أكبر من الكمية القابلة للإرجاع');
      }

      final unitPrice = sale.read<double>('unit_price');
      final returnAmount = quantity * unitPrice;
      final alreadyRefunded = sale.read<double>('refunded_amount');
      final refundableOriginalPaid =
          sale.read<double>('paid_amount') - alreadyRefunded;
      final actualRefund = refundAmount ??
          (refundableOriginalPaid <= 0
              ? 0.0
              : (refundableOriginalPaid < returnAmount
                  ? refundableOriginalPaid
                  : returnAmount));
      if (actualRefund < 0 || actualRefund - returnAmount > 0.001) {
        throw ArgumentError('مبلغ رد المرتجع غير صالح');
      }
      if (actualRefund - refundableOriginalPaid > 0.001) {
        throw ArgumentError(
            'لا يمكن رد مبلغ أكبر من المدفوع في فاتورة البيع الأصلية');
      }
      if (actualRefund > 0 &&
          refundMethod != 'CASH' &&
          refundMethod != 'TRANSFER') {
        throw ArgumentError('يجب تحديد وسيلة رد المبلغ');
      }
      if (sale.read<String>('sale_type') == 'CASH' &&
          sale.readNullable<int>('customer_id') == null &&
          (returnAmount - actualRefund).abs() > 0.001) {
        throw ArgumentError('البيع النقدي المباشر يجب رد قيمته عند الإرجاع');
      }

      final totalCogs = sale.readNullable<double>('cogs_amount');
      final returnedCogs =
          totalCogs == null ? null : totalCogs * quantity / soldQuantity;
      final now = DateTime.now().millisecondsSinceEpoch;
      final returnId = await customInsert(
        '''
        INSERT INTO sale_returns (
          sale_id, quantity, amount, cogs_amount, cost_status,
          refund_amount, refund_method, notes, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable<int>(saleId),
          Variable<double>(quantity),
          Variable<double>(returnAmount),
          Variable<double>(returnedCogs),
          Variable<String>(sale.read<String>('cost_status')),
          Variable<double>(actualRefund),
          Variable<String>(actualRefund > 0 ? refundMethod : null),
          Variable<String>(
              returnNotes.trim().isEmpty ? 'مرتجع' : returnNotes.trim()),
          Variable<int>(now),
        ],
      );

      final newReturnedQuantity = alreadyReturned + quantity;
      final newReturnedAmount =
          sale.read<double>('returned_amount') + returnAmount;
      final newReturnedCogs =
          sale.read<double>('returned_cogs') + (returnedCogs ?? 0.0);
      final newRefundedAmount = alreadyRefunded + actualRefund;
      final allocationRow = await customSelect(
        '''
        SELECT COALESCE(SUM(amount), 0.0) AS allocated
        FROM payment_allocations
        WHERE document_type = 'SALE' AND document_id = ?
        ''',
        variables: [Variable<int>(saleId)],
      ).getSingle();
      final allocated = allocationRow.read<double>('allocated');
      final invoiceNet = sale.read<double>('total_amount') -
          sale.read<double>('paid_amount') -
          newReturnedAmount +
          newRefundedAmount -
          allocated;
      final newRemaining = invoiceNet > 0.001 ? invoiceNet : 0.0;
      final newCredit = invoiceNet < -0.001 ? -invoiceNet : 0.0;
      final fullyReturned =
          (soldQuantity - newReturnedQuantity).abs() <= 0.000001;
      final oldProvisional = sale.read<double>('provisional_quantity');
      final provisionalReturned =
          quantity < oldProvisional ? quantity : oldProvisional;
      final oldProvisionalCost = sale.read<double>('provisional_cost_amount');
      final provisionalUnitCost =
          oldProvisional > 0 ? oldProvisionalCost / oldProvisional : 0.0;

      await customUpdate(
        '''
        UPDATE sales
        SET returned_quantity = ?, returned_amount = ?, returned_cogs = ?,
            refunded_amount = ?, remaining_amount = ?, credit_amount = ?,
            provisional_quantity = ?, provisional_cost_amount = ?,
            status = ?, returned_at = ?, return_notes = ?
        WHERE id = ?
        ''',
        variables: [
          Variable<double>(newReturnedQuantity),
          Variable<double>(newReturnedAmount),
          Variable<double>(newReturnedCogs),
          Variable<double>(newRefundedAmount),
          Variable<double>(newRemaining),
          Variable<double>(newCredit),
          Variable<double>(oldProvisional - provisionalReturned),
          Variable<double>(
              oldProvisionalCost - provisionalReturned * provisionalUnitCost),
          Variable<String>(fullyReturned ? 'RETURNED' : 'ACTIVE'),
          Variable<int>(now),
          Variable<String>(
              returnNotes.trim().isEmpty ? 'مرتجع' : returnNotes.trim()),
          Variable<int>(saleId),
        ],
      );

      final itemId = sale.read<int>('item_id');
      await customUpdate(
        'UPDATE items SET current_qty = current_qty + ? WHERE id = ?',
        variables: [Variable<double>(quantity), Variable<int>(itemId)],
      );

      final customerId = sale.readNullable<int>('customer_id');
      if (customerId != null) {
        await recalculateCustomerBalance(customerId);
      }
      notifyChanges();
      return returnId;
    });
  }

  /// د. تسجيل تالف (مبيعات > تالف) داخل معاملة ذرية (صفحة 7، TC-07)
  Future<int> recordWastage({
    required int itemId,
    required double quantity,
    required String notes,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('يجب تحديد الكمية التالفة أكبر من صفر');
    }

    return await transaction(() async {
      final itemRow = await customSelect(
        '''
        SELECT average_cost, cost_status, last_buy_price, default_sell_price
        FROM items WHERE id = ?
        ''',
        variables: [Variable<int>(itemId)],
      ).getSingle();

      final averageCost = itemRow.read<double>('average_cost');
      final itemCostStatus = itemRow.read<String>('cost_status');
      final lastBuy = itemRow.read<double>('last_buy_price');
      final fallbackPrice = itemRow.read<double>('default_sell_price');
      final unitCost = averageCost > 0
          ? averageCost
          : (lastBuy > 0 ? lastBuy : fallbackPrice);
      final estimatedCost = quantity * unitCost;
      final costStatus =
          averageCost > 0 && itemCostStatus == 'FINAL' ? 'FINAL' : 'UNKNOWN';
      final now = DateTime.now().millisecondsSinceEpoch;

      final wastageId = await customInsert(
        '''
        INSERT INTO wastage_records (
          item_id, quantity, estimated_cost, cost_status, notes,
          is_reversed, created_at
        ) VALUES (?, ?, ?, ?, ?, 0, ?)
        ''',
        variables: [
          Variable<int>(itemId),
          Variable<double>(quantity),
          Variable<double>(estimatedCost),
          Variable<String>(costStatus),
          Variable<String>(
              notes.trim().isEmpty ? 'قات بايت / تالف' : notes.trim()),
          Variable<int>(now),
        ],
      );

      // إنقاص الكمية المتاحة من الصنف (لا يتأثر الصندوق ولا حسابات الزبائن)
      await customUpdate(
        'UPDATE items SET current_qty = current_qty - ? WHERE id = ?',
        variables: [
          Variable<double>(quantity),
          Variable<int>(itemId),
        ],
      );

      notifyChanges();
      return wastageId;
    });
  }

  /// إمكانية التراجع عن حركة التالف إذا سُجلت بالخطأ (صفحة 7)
  Future<void> reverseWastage(int wastageId) async {
    await transaction(() async {
      final rows = await customSelect(
        'SELECT * FROM wastage_records WHERE id = ? AND is_reversed = 0',
        variables: [Variable<int>(wastageId)],
      ).get();
      if (rows.isEmpty) return;

      final row = rows.first;
      final itemId = row.read<int>('item_id');
      final qty = row.read<double>('quantity');

      await customUpdate(
        'UPDATE wastage_records SET is_reversed = 1 WHERE id = ?',
        variables: [Variable<int>(wastageId)],
      );

      await customUpdate(
        'UPDATE items SET current_qty = current_qty + ? WHERE id = ?',
        variables: [
          Variable<double>(qty),
          Variable<int>(itemId),
        ],
      );

      notifyChanges();
    });
  }

  Future<List<SaleEntity>> getSales(
      {int? customerId, bool activeOnly = false}) async {
    final clauses = <String>[];
    final vars = <Variable>[];

    if (customerId != null) {
      clauses.add('s.customer_id = ?');
      vars.add(Variable<int>(customerId));
    }
    if (activeOnly) {
      clauses.add("s.status = 'ACTIVE'");
    }

    final whereSql = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = await customSelect(
      '''
      SELECT s.*, i.name AS item_name, c.name AS customer_name
      FROM sales s
      JOIN items i ON s.item_id = i.id
      LEFT JOIN customers c ON s.customer_id = c.id
      $whereSql
      ORDER BY s.created_at DESC, s.id DESC
      ''',
      variables: vars,
    ).get();

    return rows.map((r) {
      final retMillis = r.readNullable<int>('returned_at');
      return SaleEntity(
        id: r.read<int>('id'),
        itemId: r.read<int>('item_id'),
        itemName: r.read<String>('item_name'),
        saleType: r.read<String>('sale_type'),
        customerId: r.readNullable<int>('customer_id'),
        customerName: r.readNullable<String>('customer_name'),
        quantity: r.read<double>('quantity'),
        unitPrice: r.read<double>('unit_price'),
        totalAmount: r.read<double>('total_amount'),
        paidAmount: r.read<double>('paid_amount'),
        remainingAmount: r.read<double>('remaining_amount'),
        paymentMethod: r.read<String>('payment_method'),
        cogsAmount: r.readNullable<double>('cogs_amount'),
        costStatus: r.read<String>('cost_status'),
        provisionalQuantity: r.read<double>('provisional_quantity'),
        returnedQuantity: r.read<double>('returned_quantity'),
        returnedAmount: r.read<double>('returned_amount'),
        returnedCogs: r.read<double>('returned_cogs'),
        refundedAmount: r.read<double>('refunded_amount'),
        creditAmount: r.read<double>('credit_amount'),
        status: r.read<String>('status'),
        returnedAt: retMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(retMillis)
            : null,
        returnNotes: r.readNullable<String>('return_notes'),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
      );
    }).toList();
  }

  Stream<List<SaleEntity>> watchSales() async* {
    yield await getSales();
    await for (final _ in onDatabaseChanged) {
      yield await getSales();
    }
  }

  Future<List<SaleReturnEntity>> getSaleReturns({int? saleId}) async {
    final rows = await customSelect(
      '''
      SELECT * FROM sale_returns
      ${saleId == null ? '' : 'WHERE sale_id = ?'}
      ORDER BY created_at DESC, id DESC
      ''',
      variables: saleId == null ? const [] : [Variable<int>(saleId)],
    ).get();
    return rows
        .map(
          (r) => SaleReturnEntity(
            id: r.read<int>('id'),
            saleId: r.read<int>('sale_id'),
            quantity: r.read<double>('quantity'),
            amount: r.read<double>('amount'),
            cogsAmount: r.readNullable<double>('cogs_amount'),
            costStatus: r.read<String>('cost_status'),
            refundAmount: r.read<double>('refund_amount'),
            refundMethod: r.readNullable<String>('refund_method'),
            notes: r.readNullable<String>('notes'),
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
          ),
        )
        .toList();
  }

  Future<List<WastageEntity>> getWastageRecords() async {
    final rows = await customSelect('''
      SELECT w.*, i.name AS item_name
      FROM wastage_records w
      JOIN items i ON w.item_id = i.id
      WHERE w.is_reversed = 0
      ORDER BY w.created_at DESC, w.id DESC
    ''').get();

    return rows.map((r) {
      return WastageEntity(
        id: r.read<int>('id'),
        itemId: r.read<int>('item_id'),
        itemName: r.read<String>('item_name'),
        quantity: r.read<double>('quantity'),
        estimatedCost: r.read<double>('estimated_cost'),
        costStatus: r.read<String>('cost_status'),
        notes: r.read<String>('notes'),
        isReversed: r.read<int>('is_reversed') == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
      );
    }).toList();
  }

  Stream<List<WastageEntity>> watchWastageRecords() async* {
    yield await getWastageRecords();
    await for (final _ in onDatabaseChanged) {
      yield await getWastageRecords();
    }
  }

  // ===========================================================================
  // سابعًا: السدادات (قبض من زبون / صرف لمورد - نقد أو حوالة - صفحة 7، TC-04)
  // ===========================================================================
  Future<int> recordPayment({
    required String partyType, // 'CUSTOMER' or 'SUPPLIER'
    required int partyId,
    required double amount,
    required String method, // 'CASH' or 'TRANSFER'
    String? transferCompany,
    String? transferNumber,
    String? notes,
    String? requestKey,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ السداد أكبر من صفر');
    }
    if (partyType != 'CUSTOMER' && partyType != 'SUPPLIER') {
      throw ArgumentError('نوع الطرف غير صالح');
    }
    if (method != 'CASH' && method != 'TRANSFER') {
      throw ArgumentError('وسيلة السداد غير صالحة');
    }

    return await transaction(() async {
      final existing = await _existingOperationId('PAYMENT', requestKey);
      if (existing != null) return existing;

      final partyTable = partyType == 'CUSTOMER' ? 'customers' : 'suppliers';
      final partyRows = await customSelect(
        'SELECT id FROM $partyTable WHERE id = ?',
        variables: [Variable<int>(partyId)],
      ).get();
      if (partyRows.isEmpty) throw StateError('الحساب المحدد غير موجود');

      final now = DateTime.now().millisecondsSinceEpoch;
      final paymentId = await customInsert(
        '''
        INSERT INTO payments (
          party_type, party_id, amount, method, transfer_company,
          transfer_number, notes, is_reversed, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
        ''',
        variables: [
          Variable<String>(partyType),
          Variable<int>(partyId),
          Variable<double>(amount),
          Variable<String>(method),
          Variable<String>(transferCompany?.trim()),
          Variable<String>(transferNumber?.trim()),
          Variable<String>(notes?.trim()),
          Variable<int>(now),
        ],
      );

      var amountToAllocate = amount;
      final documentType = partyType == 'CUSTOMER' ? 'SALE' : 'PURCHASE';
      final documentTable = partyType == 'CUSTOMER' ? 'sales' : 'purchases';
      final partyColumn =
          partyType == 'CUSTOMER' ? 'customer_id' : 'supplier_id';
      final extraClause = partyType == 'CUSTOMER'
          ? "AND sale_type = 'CREDIT'"
          : 'AND is_reversed = 0';
      final documents = await customSelect(
        '''
        SELECT id, remaining_amount FROM $documentTable
        WHERE $partyColumn = ? AND remaining_amount > 0.001 $extraClause
        ORDER BY created_at ASC, id ASC
        ''',
        variables: [Variable<int>(partyId)],
      ).get();

      for (final document in documents) {
        if (amountToAllocate <= 0.001) break;
        final remaining = document.read<double>('remaining_amount');
        final allocated =
            amountToAllocate < remaining ? amountToAllocate : remaining;
        final newRemaining = remaining - allocated;
        await customInsert(
          '''
          INSERT INTO payment_allocations (
            payment_id, document_type, document_id, amount, created_at
          ) VALUES (?, ?, ?, ?, ?)
          ''',
          variables: [
            Variable<int>(paymentId),
            Variable<String>(documentType),
            Variable<int>(document.read<int>('id')),
            Variable<double>(allocated),
            Variable<int>(now),
          ],
        );
        if (partyType == 'SUPPLIER') {
          await customUpdate(
            '''
            UPDATE purchases SET remaining_amount = ?, is_settled = ?
            WHERE id = ?
            ''',
            variables: [
              Variable<double>(newRemaining),
              Variable<int>(newRemaining <= 0.001 ? 1 : 0),
              Variable<int>(document.read<int>('id')),
            ],
          );
        } else {
          await customUpdate(
            'UPDATE sales SET remaining_amount = ? WHERE id = ?',
            variables: [
              Variable<double>(newRemaining),
              Variable<int>(document.read<int>('id')),
            ],
          );
        }
        amountToAllocate -= allocated;
      }

      if (partyType == 'CUSTOMER') {
        await recalculateCustomerBalance(partyId);
      } else if (partyType == 'SUPPLIER') {
        await recalculateSupplierBalance(partyId);
      }

      await _rememberOperation('PAYMENT', requestKey, paymentId, now);

      notifyChanges();
      return paymentId;
    });
  }

  Future<List<PaymentEntity>> getPayments(
      {String? partyType, int? partyId}) async {
    final clauses = <String>['p.is_reversed = 0'];
    final vars = <Variable>[];

    if (partyType != null) {
      clauses.add('p.party_type = ?');
      vars.add(Variable<String>(partyType));
    }
    if (partyId != null) {
      clauses.add('p.party_id = ?');
      vars.add(Variable<int>(partyId));
    }

    final whereSql = 'WHERE ${clauses.join(' AND ')}';
    final rows = await customSelect(
      '''
      SELECT p.*,
        CASE
          WHEN p.party_type = 'CUSTOMER' THEN (SELECT name FROM customers WHERE id = p.party_id)
          ELSE (SELECT name FROM suppliers WHERE id = p.party_id)
        END AS party_name
      FROM payments p
      $whereSql
      ORDER BY p.created_at DESC, p.id DESC
      ''',
      variables: vars,
    ).get();

    return rows.map((r) {
      return PaymentEntity(
        id: r.read<int>('id'),
        partyType: r.read<String>('party_type'),
        partyId: r.read<int>('party_id'),
        partyName: r.readNullable<String>('party_name') ?? 'غير معروف',
        amount: r.read<double>('amount'),
        method: r.read<String>('method'),
        transferCompany: r.readNullable<String>('transfer_company'),
        transferNumber: r.readNullable<String>('transfer_number'),
        notes: r.readNullable<String>('notes'),
        isReversed: r.read<int>('is_reversed') == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
      );
    }).toList();
  }

  // ===========================================================================
  // ثامنًا: المصاريف (مصاريف العمل / مصاريف شخصية - صفحة 7، TC-05)
  // ===========================================================================
  Future<int> recordExpense({
    required String categoryType, // 'WORK' or 'PERSONAL'
    required String title,
    required double amount,
    String paymentMethod = 'CASH',
    String? notes,
  }) async {
    if (categoryType != 'WORK' && categoryType != 'PERSONAL') {
      throw ArgumentError(
          'يجب تحديد تصنيف المصروف: مصاريف العمل أو مصاريف شخصية');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError('يرجى إدخال بند/وصف المصروف');
    }
    if (amount <= 0) {
      throw ArgumentError('يجب أن يكون مبلغ المصروف أكبر من صفر');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await customInsert(
      '''
      INSERT INTO expenses (category_type, title, amount, payment_method, notes, is_reversed, created_at)
      VALUES (?, ?, ?, ?, ?, 0, ?)
      ''',
      variables: [
        Variable<String>(categoryType),
        Variable<String>(title.trim()),
        Variable<double>(amount),
        Variable<String>(paymentMethod),
        Variable<String>(notes?.trim()),
        Variable<int>(now),
      ],
    );
    notifyChanges();
    return id;
  }

  Future<List<ExpenseEntity>> getExpenses({String? categoryType}) async {
    final clauses = <String>['is_reversed = 0'];
    final vars = <Variable>[];
    if (categoryType != null) {
      clauses.add('category_type = ?');
      vars.add(Variable<String>(categoryType));
    }

    final rows = await customSelect(
      '''
      SELECT * FROM expenses
      WHERE ${clauses.join(' AND ')}
      ORDER BY created_at DESC, id DESC
      ''',
      variables: vars,
    ).get();

    return rows.map((r) {
      return ExpenseEntity(
        id: r.read<int>('id'),
        categoryType: r.read<String>('category_type'),
        title: r.read<String>('title'),
        amount: r.read<double>('amount'),
        paymentMethod: r.read<String>('payment_method'),
        notes: r.readNullable<String>('notes'),
        isReversed: r.read<int>('is_reversed') == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
      );
    }).toList();
  }

  Stream<List<ExpenseEntity>> watchExpenses() async* {
    yield await getExpenses();
    await for (final _ in onDatabaseChanged) {
      yield await getExpenses();
    }
  }

  Future<int> recordTreasuryFunding({
    required String entryType,
    required double amount,
    String method = 'CASH',
    String? notes,
  }) async {
    if (entryType != 'OPENING' && entryType != 'CAPITAL') {
      throw ArgumentError('نوع حركة التمويل غير صالح');
    }
    if (amount <= 0) throw ArgumentError('المبلغ يجب أن يكون أكبر من صفر');
    if (method != 'CASH' && method != 'TRANSFER') {
      throw ArgumentError('وسيلة الخزينة غير صالحة');
    }
    final id = await customInsert(
      '''
      INSERT INTO treasury_entries (
        entry_type, amount, from_method, to_method, notes,
        is_reversed, created_at
      ) VALUES (?, ?, NULL, ?, ?, 0, ?)
      ''',
      variables: [
        Variable<String>(entryType),
        Variable<double>(amount),
        Variable<String>(method),
        Variable<String>(notes?.trim()),
        Variable<int>(DateTime.now().millisecondsSinceEpoch),
      ],
    );
    notifyChanges();
    return id;
  }

  Future<int> recordTreasuryTransfer({
    required String fromMethod,
    required String toMethod,
    required double amount,
    String? notes,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('مبلغ التحويل يجب أن يكون أكبر من صفر');
    }
    if ((fromMethod != 'CASH' && fromMethod != 'TRANSFER') ||
        (toMethod != 'CASH' && toMethod != 'TRANSFER') ||
        fromMethod == toMethod) {
      throw ArgumentError('يجب اختيار وسيلتي خزينة مختلفتين');
    }
    return transaction(() async {
      final summary = await getDashboardSummary();
      final available = fromMethod == 'CASH'
          ? summary.cashDrawerBalance
          : summary.transferBalance;
      if (amount - available > 0.001) {
        throw StateError('الرصيد المتاح لا يكفي لإتمام التحويل');
      }
      final id = await customInsert(
        '''
        INSERT INTO treasury_entries (
          entry_type, amount, from_method, to_method, notes,
          is_reversed, created_at
        ) VALUES ('TRANSFER', ?, ?, ?, ?, 0, ?)
        ''',
        variables: [
          Variable<double>(amount),
          Variable<String>(fromMethod),
          Variable<String>(toMethod),
          Variable<String>(notes?.trim()),
          Variable<int>(DateTime.now().millisecondsSinceEpoch),
        ],
      );
      notifyChanges();
      return id;
    });
  }

  // ===========================================================================
  // تاسعًا: ملخص التطبيق ولوحة المؤشرات الفورية (Dashboard Summary - صفحة 3 و 7)
  // ===========================================================================
  Future<DashboardSummaryEntity> getDashboardSummary() async {
    final now = DateTime.now();
    final startOfDay =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;

    // 1. مبيعات اليوم ومرتجعات اليوم (كل حدث حسب تاريخ حدوثه).
    final todaySalesRow = await customSelect(
      '''
      SELECT
        COALESCE(SUM(total_amount), 0.0) AS total_sales,
        COALESCE(SUM(paid_amount), 0.0) AS paid_sales,
        COALESCE(SUM(total_amount - paid_amount), 0.0) AS credit_sales,
        COALESCE(SUM(cogs_amount), 0.0) AS cogs,
        COALESCE(SUM(CASE WHEN cost_status != 'FINAL' THEN 1 ELSE 0 END), 0) AS uncertain_count
      FROM sales
      WHERE created_at >= ?
      ''',
      variables: [Variable<int>(startOfDay)],
    ).getSingle();

    final todayReturnsRow = await customSelect(
      '''
      SELECT
        COALESCE(SUM(amount), 0.0) AS return_sales,
        COALESCE(SUM(refund_amount), 0.0) AS refunds,
        COALESCE(SUM(cogs_amount), 0.0) AS returned_cogs,
        COALESCE(SUM(CASE WHEN cogs_amount IS NULL OR cost_status != 'FINAL' THEN 1 ELSE 0 END), 0) AS uncertain_count
      FROM sale_returns
      WHERE created_at >= ?
      ''',
      variables: [Variable<int>(startOfDay)],
    ).getSingle();

    // 2. سدادات الزبائن اليوم
    final todayCustPayRow = await customSelect(
      '''
      SELECT COALESCE(SUM(amount), 0.0) AS cust_pay
      FROM payments
      WHERE party_type = 'CUSTOMER' AND is_reversed = 0 AND created_at >= ?
      ''',
      variables: [Variable<int>(startOfDay)],
    ).getSingle();

    // 3. مشتريات اليوم
    final todayPurchRow = await customSelect(
      '''
      SELECT COALESCE(SUM(total_amount), 0.0) AS total_purch
      FROM purchases
      WHERE is_reversed = 0 AND created_at >= ?
      ''',
      variables: [Variable<int>(startOfDay)],
    ).getSingle();

    // 4. مصاريف اليوم (عمل vs شخصية)
    final todayExpRows = await customSelect(
      '''
      SELECT category_type, COALESCE(SUM(amount), 0.0) AS total_exp
      FROM expenses
      WHERE is_reversed = 0 AND created_at >= ?
      GROUP BY category_type
      ''',
      variables: [Variable<int>(startOfDay)],
    ).get();

    double todayWorkExp = 0.0;
    double todayPersonalExp = 0.0;
    for (final r in todayExpRows) {
      final cat = r.read<String>('category_type');
      final amt = r.read<double>('total_exp');
      if (cat == 'WORK') todayWorkExp = amt;
      if (cat == 'PERSONAL') todayPersonalExp = amt;
    }

    // 5. التالف اليوم
    final todayWastageRow = await customSelect(
      '''
      SELECT
        COALESCE(SUM(estimated_cost), 0.0) AS total_wastage,
        COALESCE(SUM(CASE WHEN cost_status != 'FINAL' THEN 1 ELSE 0 END), 0) AS uncertain_count
      FROM wastage_records
      WHERE is_reversed = 0 AND created_at >= ?
      ''',
      variables: [Variable<int>(startOfDay)],
    ).getSingle();

    // 6. حساب الصندوق النقدي الفعلي (الدرج) ورصيد الحوالات البنكية عبر كل الحركات النشطة
    Future<double> calcTreasuryByMethod(String method) async {
      final salesIn = (await customSelect(
        "SELECT COALESCE(SUM(paid_amount), 0.0) AS val FROM sales WHERE payment_method = ?",
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      final custPayIn = (await customSelect(
        "SELECT COALESCE(SUM(amount), 0.0) AS val FROM payments WHERE party_type = 'CUSTOMER' AND is_reversed = 0 AND method = ?",
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      final purchOut = (await customSelect(
        "SELECT COALESCE(SUM(paid_amount), 0.0) AS val FROM purchases WHERE is_reversed = 0 AND payment_method = ?",
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      final supPayOut = (await customSelect(
        "SELECT COALESCE(SUM(amount), 0.0) AS val FROM payments WHERE party_type = 'SUPPLIER' AND is_reversed = 0 AND method = ?",
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      final expOut = (await customSelect(
        "SELECT COALESCE(SUM(amount), 0.0) AS val FROM expenses WHERE is_reversed = 0 AND payment_method = ?",
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      final refundsOut = (await customSelect(
        '''
        SELECT COALESCE(SUM(refund_amount), 0.0) AS val
        FROM sale_returns WHERE refund_method = ?
        ''',
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      final treasuryIn = (await customSelect(
        '''
        SELECT COALESCE(SUM(amount), 0.0) AS val
        FROM treasury_entries
        WHERE is_reversed = 0 AND to_method = ?
        ''',
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      final treasuryOut = (await customSelect(
        '''
        SELECT COALESCE(SUM(amount), 0.0) AS val
        FROM treasury_entries
        WHERE is_reversed = 0 AND entry_type = 'TRANSFER' AND from_method = ?
        ''',
        variables: [Variable<String>(method)],
      ).getSingle())
          .read<double>('val');

      return (salesIn + custPayIn + treasuryIn) -
          (purchOut + supPayOut + expOut + refundsOut + treasuryOut);
    }

    final cashDrawer = await calcTreasuryByMethod('CASH');
    final transferBal = await calcTreasuryByMethod('TRANSFER');

    // 7. إجمالي أرصدة الزبائن والموردين
    final custTotals = await customSelect('''
      SELECT
        COALESCE(SUM(balance_alayh), 0.0) AS total_alayh,
        COALESCE(SUM(balance_lah), 0.0) AS total_lah
      FROM customers WHERE is_active = 1
    ''').getSingle();

    final supTotals = await customSelect('''
      SELECT
        COALESCE(SUM(balance_lah), 0.0) AS total_lah,
        COALESCE(SUM(balance_alayh), 0.0) AS total_alayh
      FROM suppliers WHERE is_active = 1
    ''').getSingle();

    final todayTotalSales = todaySalesRow.read<double>('total_sales') -
        todayReturnsRow.read<double>('return_sales');
    final todayPaidSales = todaySalesRow.read<double>('paid_sales') -
        todayReturnsRow.read<double>('refunds');
    final todayCreditSales = todaySalesRow.read<double>('credit_sales');
    final todayCustPay = todayCustPayRow.read<double>('cust_pay');
    final todayPurchasesTotal = todayPurchRow.read<double>('total_purch');
    final todayWastageCost = todayWastageRow.read<double>('total_wastage');
    final todayCogs = todaySalesRow.read<double>('cogs') -
        todayReturnsRow.read<double>('returned_cogs');
    final todayProfitIsReliable =
        todaySalesRow.read<int>('uncertain_count') == 0 &&
            todayReturnsRow.read<int>('uncertain_count') == 0 &&
            todayWastageRow.read<int>('uncertain_count') == 0;

    final netWorkProfit = CalculateBalanceService.computeDailyWorkNetProfit(
      netSalesAfterReturns: todayTotalSales,
      costOfGoodsSold: todayCogs,
      totalWastageCost: todayWastageCost,
      workExpenses: todayWorkExp,
    );

    return DashboardSummaryEntity(
      todayTotalSales: todayTotalSales,
      todayCashSales: todayPaidSales,
      todayCreditSales: todayCreditSales,
      todayCollectedFromCustomers: todayPaidSales + todayCustPay,
      todayPurchasesTotal: todayPurchasesTotal,
      todayWorkExpenses: todayWorkExp,
      todayPersonalExpenses: todayPersonalExp,
      todayWastageCost: todayWastageCost,
      todayCogs: todayCogs,
      todayNetWorkProfit: netWorkProfit,
      todayProfitIsReliable: todayProfitIsReliable,
      cashDrawerBalance: cashDrawer,
      transferBalance: transferBal,
      totalCustomersAlayh: custTotals.read<double>('total_alayh'),
      totalCustomersLah: custTotals.read<double>('total_lah'),
      totalSuppliersLah: supTotals.read<double>('total_lah'),
      totalSuppliersAlayh: supTotals.read<double>('total_alayh'),
    );
  }

  Stream<DashboardSummaryEntity> watchDashboardSummary() async* {
    yield await getDashboardSummary();
    await for (final _ in onDatabaseChanged) {
      yield await getDashboardSummary();
    }
  }

  // ===========================================================================
  // عاشرًا: سجل «آخر العمليات» الموحد وكشوفات الحساب التفصيلية (Statements)
  // ===========================================================================
  Future<List<UnifiedOperationEntity>> getRecentUnifiedOperations(
      {int limit = 50}) async {
    final ops = <UnifiedOperationEntity>[];

    final sales = await getSales();
    for (final s in sales.take(limit)) {
      ops.add(
        UnifiedOperationEntity(
          idKey: 'SALE_${s.id}',
          type: 'SALE',
          title: 'بيع ${s.saleType == 'CASH' ? 'نقد' : 'آجل'}: ${s.itemName}',
          subtitle: s.customerName != null
              ? 'الزبون: ${s.customerName}'
              : 'بيع مباشر (${s.quantity.toInt()} ربطة)',
          amount: s.totalAmount,
          paymentMethod: s.paymentMethod,
          createdAt: s.createdAt,
          isPositiveCash: s.paidAmount > 0,
        ),
      );
    }

    final returns = await getSaleReturns();
    for (final saleReturn in returns.take(limit)) {
      ops.add(
        UnifiedOperationEntity(
          idKey: 'RETURN_${saleReturn.id}',
          type: 'RETURN',
          title: 'مرتجع مبيعات',
          subtitle:
              'كمية ${saleReturn.quantity} | رد نقدي/حوالة: ${saleReturn.refundAmount}',
          amount: saleReturn.amount,
          paymentMethod: saleReturn.refundMethod ?? 'CREDIT',
          createdAt: saleReturn.createdAt,
          isPositiveCash: false,
        ),
      );
    }

    final purchases = await getPurchases();
    for (final p in purchases.take(limit)) {
      ops.add(
        UnifiedOperationEntity(
          idKey: 'PURCHASE_${p.id}',
          type: 'PURCHASE',
          title: 'شراء ${p.itemName} (${p.quantity.toInt()} ربطة)',
          subtitle:
              'المورد: ${p.supplierName} | المدفوع: ${p.paidAmount.toInt()}',
          amount: p.totalAmount,
          paymentMethod: p.paymentMethod,
          createdAt: p.createdAt,
          isPositiveCash: false,
        ),
      );
    }

    final payments = await getPayments();
    for (final pay in payments.take(limit)) {
      final isCust = pay.partyType == 'CUSTOMER';
      ops.add(
        UnifiedOperationEntity(
          idKey: 'PAY_${pay.id}',
          type: isCust ? 'CUSTOMER_PAY' : 'SUPPLIER_PAY',
          title: isCust
              ? 'قبض سداد من زبون: ${pay.partyName}'
              : 'صرف سداد لمورد: ${pay.partyName}',
          subtitle: pay.method == 'TRANSFER'
              ? 'حوالة (${pay.transferCompany ?? ''} ${pay.transferNumber ?? ''})'
              : 'نقد في الصندوق',
          amount: pay.amount,
          paymentMethod: pay.method,
          createdAt: pay.createdAt,
          isPositiveCash: isCust,
        ),
      );
    }

    final expenses = await getExpenses();
    for (final e in expenses.take(limit)) {
      ops.add(
        UnifiedOperationEntity(
          idKey: 'EXP_${e.id}',
          type: 'EXPENSE',
          title:
              '${e.categoryType == 'WORK' ? 'مصروف عمل' : 'مصروف شخصي'}: ${e.title}',
          subtitle: e.notes ?? (e.paymentMethod == 'CASH' ? 'نقد' : 'حوالة'),
          amount: e.amount,
          paymentMethod: e.paymentMethod,
          createdAt: e.createdAt,
          isPositiveCash: false,
        ),
      );
    }

    final wastages = await getWastageRecords();
    for (final w in wastages.take(limit)) {
      ops.add(
        UnifiedOperationEntity(
          idKey: 'WASTE_${w.id}',
          type: 'WASTAGE',
          title: 'تالف قات: ${w.itemName} (${w.quantity.toInt()} ربطة)',
          subtitle: w.notes,
          amount: w.estimatedCost,
          paymentMethod: 'NONE',
          createdAt: w.createdAt,
          isPositiveCash: false,
        ),
      );
    }

    ops.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ops.take(limit).toList();
  }

  Stream<List<UnifiedOperationEntity>> watchRecentUnifiedOperations(
      {int limit = 50}) async* {
    yield await getRecentUnifiedOperations(limit: limit);
    await for (final _ in onDatabaseChanged) {
      yield await getRecentUnifiedOperations(limit: limit);
    }
  }

  /// استخراج كشف حساب تفصيلي («مفصل») للزبون بالحركات والرصيد التراكمي
  Future<List<StatementLineEntity>> getCustomerStatement(int customerId) async {
    final sales = await getSales(customerId: customerId);
    final payments =
        await getPayments(partyType: 'CUSTOMER', partyId: customerId);

    final rawEvents = <({
      DateTime date,
      String type,
      String desc,
      double alayh,
      double lah
    })>[];

    for (final s in sales) {
      rawEvents.add((
        date: s.createdAt,
        type: 'فاتورة بيع آجل',
        desc:
            '${s.itemName} (${s.quantity.toInt()} × ${s.unitPrice.toInt()})${s.paidAmount > 0 ? ' - مدفوع: ${s.paidAmount.toInt()}' : ''}',
        alayh: s.totalAmount - s.paidAmount,
        lah: 0.0,
      ));
      final returns = await getSaleReturns(saleId: s.id);
      for (final saleReturn in returns) {
        rawEvents.add((
          date: saleReturn.createdAt,
          type: 'مرتجع بيع',
          desc:
              'إرجاع ${saleReturn.quantity} ${s.itemName} (${saleReturn.notes ?? ''})',
          alayh: 0.0,
          lah: saleReturn.amount - saleReturn.refundAmount,
        ));
      }
    }

    for (final p in payments) {
      rawEvents.add((
        date: p.createdAt,
        type: p.method == 'CASH' ? 'سداد نقدي' : 'سداد حوالة',
        desc: p.method == 'TRANSFER'
            ? '${p.transferCompany ?? 'حوالة'} رقم: ${p.transferNumber ?? '-'}'
            : (p.notes ?? 'سند قبض نقدي'),
        alayh: 0.0,
        lah: p.amount,
      ));
    }

    rawEvents.sort((a, b) => a.date.compareTo(b.date));

    double runningNet = 0.0; // موجب = عليه، سالب = له
    final lines = <StatementLineEntity>[];
    for (final ev in rawEvents) {
      runningNet += (ev.alayh - ev.lah);
      String label = 'مصفر';
      if (runningNet > 0.001) label = 'عليه';
      if (runningNet < -0.001) label = 'له';

      lines.add(
        StatementLineEntity(
          date: ev.date,
          operationType: ev.type,
          description: ev.desc,
          debitAlayh: ev.alayh,
          creditLah: ev.lah,
          runningBalance: runningNet.abs(),
          balanceLabel: label,
        ),
      );
    }

    return lines.reversed.toList();
  }

  /// استخراج كشف حساب تفصيلي («مفصل») للمورد بجميع عمليات الشراء والمدفوعات
  Future<List<StatementLineEntity>> getSupplierStatement(int supplierId) async {
    final purchases = await getPurchases(supplierId: supplierId);
    final payments =
        await getPayments(partyType: 'SUPPLIER', partyId: supplierId);

    final rawEvents = <({
      DateTime date,
      String type,
      String desc,
      double lah,
      double alayh
    })>[];

    for (final p in purchases) {
      final rem = p.totalAmount - p.paidAmount;
      rawEvents.add((
        date: p.createdAt,
        type: 'فاتورة شراء',
        desc:
            '${p.itemName} (${p.quantity.toInt()} × ${p.unitPrice.toInt()}) - الإجمالي: ${p.totalAmount.toInt()} - المدفوع: ${p.paidAmount.toInt()}',
        lah: rem > 0 ? rem : 0.0,
        alayh: rem < 0 ? rem.abs() : 0.0,
      ));
    }

    for (final pay in payments) {
      rawEvents.add((
        date: pay.createdAt,
        type: pay.method == 'CASH' ? 'سداد نقدي للمورد' : 'سداد حوالة للمورد',
        desc: pay.method == 'TRANSFER'
            ? '${pay.transferCompany ?? 'حوالة'} رقم: ${pay.transferNumber ?? '-'}'
            : (pay.notes ?? 'دفعة نقدية'),
        lah: 0.0,
        alayh: pay.amount,
      ));
    }

    rawEvents.sort((a, b) => a.date.compareTo(b.date));

    double runningNet = 0.0; // موجب = له، سالب = عليه
    final lines = <StatementLineEntity>[];
    for (final ev in rawEvents) {
      runningNet += (ev.lah - ev.alayh);
      String label = 'مصفر';
      if (runningNet > 0.001) label = 'له';
      if (runningNet < -0.001) label = 'عليه';

      lines.add(
        StatementLineEntity(
          date: ev.date,
          operationType: ev.type,
          description: ev.desc,
          debitAlayh: ev.alayh,
          creditLah: ev.lah,
          runningBalance: runningNet.abs(),
          balanceLabel: label,
        ),
      );
    }

    return lines.reversed.toList();
  }

  /// تصفير البيانات التجريبية مع الحفاظ على الإعدادات والأصناف الأساسية (صفحة 4)
  Future<void> resetTransactionalData() async {
    await transaction(() async {
      await customStatement('DELETE FROM payment_allocations');
      await customStatement('DELETE FROM sale_returns');
      await customStatement('DELETE FROM operation_requests');
      await customStatement('DELETE FROM sales');
      await customStatement('DELETE FROM purchases');
      await customStatement('DELETE FROM payments');
      await customStatement('DELETE FROM expenses');
      await customStatement('DELETE FROM wastage_records');
      await customStatement('DELETE FROM treasury_entries');
      await customStatement('DELETE FROM customers');
      // Items are intentionally retained. Detach their optional supplier link
      // before deleting suppliers so foreign_keys=ON cannot leave a partial reset.
      await customStatement('UPDATE items SET default_supplier_id = NULL');
      await customStatement('DELETE FROM suppliers');
      await customStatement(
          "UPDATE items SET current_qty = 0, last_buy_price = 0, average_cost = 0, cost_status = 'FINAL'");
      notifyChanges();
    });
  }

  /// تنفيذ دمج الحركات المؤقتة قبل النسخ الاحتياطي لضمان عدم تلف الملف (صفحة 10)
  Future<void> flushWalCheckpoint() async {
    await customStatement('PRAGMA wal_checkpoint(FULL)');
  }

  /// فحص سلامة قاعدة البيانات قبل اعتماد النسخة المستعادة (صفحة 10)
  Future<bool> checkIntegrity() async {
    final row = await customSelect('PRAGMA integrity_check').getSingle();
    final result = row.data.values.first?.toString().toLowerCase() ?? '';
    if (result != 'ok') return false;
    final foreignKeyErrors =
        await customSelect('PRAGMA foreign_key_check').get();
    return foreignKeyErrors.isEmpty;
  }

  /// Creates a transactionally consistent standalone SQLite snapshot. SQLite
  /// performs the copy itself, so WAL contents are included safely.
  Future<void> createConsistentSnapshot(String destinationPath) async {
    final escaped = destinationPath.replaceAll("'", "''");
    final destination = File(destinationPath);
    if (await destination.exists()) {
      await destination.delete();
    }
    await customStatement("VACUUM INTO '$escaped'");
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, AppConstants.dbFileName));
    return NativeDatabase.createInBackground(file);
  });
}
