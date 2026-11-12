import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqwati/core/constants/app_constants.dart';
import 'package:maqwati/data/backup/google_drive_backup_service.dart';
import 'package:maqwati/data/local_db/app_database.dart';
import 'package:maqwati/domain/services/pin_security_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  group('Accounting v2 invariants', () {
    late AppDatabase db;
    late int itemId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.getAppSettings();
      itemId = (await db.getAllItems()).first.id;
    });

    tearDown(() async {
      await db.close();
    });

    test('TC-01/03/14: COGS profit scenario equals 2,000', () async {
      final supplierId = await db.saveSupplier(name: 'مورد التكلفة');
      await db.recordSupplierPurchase(
        supplierId: supplierId,
        itemId: itemId,
        quantity: 10,
        unitPrice: 1000,
        paidAmount: 10000,
      );
      await db.recordSale(
        itemId: itemId,
        saleType: 'CASH',
        quantity: 4,
        unitPrice: 2000,
      );
      await db.recordWastage(
        itemId: itemId,
        quantity: 2,
        notes: 'اختبار تكلفة',
      );

      final summary = await db.getDashboardSummary();
      final item = (await db.getAllItems()).firstWhere((i) => i.id == itemId);
      expect(summary.todayTotalSales, 8000);
      expect(summary.todayCogs, 4000);
      expect(summary.todayWastageCost, 2000);
      expect(summary.todayNetWorkProfit, 2000);
      expect(summary.todayProfitIsReliable, isTrue);
      expect(item.currentQty, 4);
    });

    test('TC-06/07/08: customer payment allocates once and exposes credit',
        () async {
      final customerId = await db.saveCustomer(name: 'زبون الدفعات');
      await db.recordSale(
        itemId: itemId,
        saleType: 'CREDIT',
        customerId: customerId,
        quantity: 1,
        unitPrice: 3000,
        paidAmount: 0,
      );
      await db.recordSale(
        itemId: itemId,
        saleType: 'CREDIT',
        customerId: customerId,
        quantity: 1,
        unitPrice: 4000,
        paidAmount: 0,
      );

      await db.recordPayment(
        partyType: 'CUSTOMER',
        partyId: customerId,
        amount: 8000,
        method: 'CASH',
      );

      final sales = await db.getSales(customerId: customerId);
      final customer = await db.getCustomerById(customerId);
      expect(sales.every((sale) => sale.remainingAmount == 0), isTrue);
      expect(customer!.balanceAlayh, 0);
      expect(customer.balanceLah, 1000);
    });

    test('TC-09: supplier FIFO allocation updates each invoice remaining',
        () async {
      final supplierId = await db.saveSupplier(name: 'مورد FIFO');
      await db.recordSupplierPurchase(
        supplierId: supplierId,
        itemId: itemId,
        quantity: 2,
        unitPrice: 1000,
        paidAmount: 0,
      );
      await db.recordSupplierPurchase(
        supplierId: supplierId,
        itemId: itemId,
        quantity: 3,
        unitPrice: 1000,
        paidAmount: 0,
      );
      await db.recordPayment(
        partyType: 'SUPPLIER',
        partyId: supplierId,
        amount: 2500,
        method: 'TRANSFER',
      );

      final invoices = (await db.getPurchases(supplierId: supplierId))
        ..sort((a, b) => a.id.compareTo(b.id));
      expect(invoices.first.remainingAmount, 0);
      expect(invoices.first.isSettled, isTrue);
      expect(invoices.last.remainingAmount, 2500);
      expect((await db.getSupplierById(supplierId))!.balanceLah, 2500);
    });

    test('TC-10/13: partial cash return restores quantity and COGS once',
        () async {
      final supplierId = await db.saveSupplier(name: 'مورد المرتجع');
      await db.recordSupplierPurchase(
        supplierId: supplierId,
        itemId: itemId,
        quantity: 10,
        unitPrice: 1000,
        paidAmount: 10000,
      );
      final saleId = await db.recordSale(
        itemId: itemId,
        saleType: 'CASH',
        quantity: 4,
        unitPrice: 2000,
      );
      await db.returnSalePartial(
        saleId: saleId,
        quantity: 1,
        refundAmount: 2000,
        refundMethod: 'CASH',
      );

      final sale = (await db.getSales()).single;
      final summary = await db.getDashboardSummary();
      final item = (await db.getAllItems()).firstWhere((i) => i.id == itemId);
      expect(sale.returnedQuantity, 1);
      expect(sale.status, 'ACTIVE');
      expect(summary.todayTotalSales, 6000);
      expect(summary.todayCogs, 3000);
      expect(summary.cashDrawerBalance, -4000);
      expect(item.currentQty, 7);
      expect(
        () => db.returnSalePartial(
          saleId: saleId,
          quantity: 4,
          refundAmount: 8000,
          refundMethod: 'CASH',
        ),
        throwsArgumentError,
      );
    });

    test('TC-10: full cash return subtracts the refund exactly once', () async {
      final saleId = await db.recordSale(
        itemId: itemId,
        saleType: 'CASH',
        quantity: 1,
        unitPrice: 5000,
      );
      expect((await db.getDashboardSummary()).cashDrawerBalance, 5000);

      await db.returnSalePartial(
        saleId: saleId,
        quantity: 1,
        refundAmount: 5000,
        refundMethod: 'CASH',
      );

      final summary = await db.getDashboardSummary();
      expect((await db.getSales()).single.status, 'RETURNED');
      expect(summary.cashDrawerBalance, 0);
      expect(summary.todayTotalSales, 0);
    });

    test('TC-12: return after collection becomes explicit customer credit',
        () async {
      final customerId = await db.saveCustomer(name: 'زبون مرتجع لاحق');
      final saleId = await db.recordSale(
        itemId: itemId,
        saleType: 'CREDIT',
        customerId: customerId,
        quantity: 1,
        unitPrice: 5000,
        paidAmount: 0,
      );
      await db.recordPayment(
        partyType: 'CUSTOMER',
        partyId: customerId,
        amount: 5000,
        method: 'CASH',
      );
      await db.returnSale(saleId: saleId);

      final customer = await db.getCustomerById(customerId);
      expect(customer!.balanceAlayh, 0);
      expect(customer.balanceLah, 5000);
      expect((await db.getDashboardSummary()).cashDrawerBalance, 5000);
    });

    test('TC-15: reversing wastage restores stock exactly once', () async {
      final wastageId = await db.recordWastage(
        itemId: itemId,
        quantity: 2,
        notes: 'تالف',
      );
      await db.reverseWastage(wastageId);
      await db.reverseWastage(wastageId);
      final item = (await db.getAllItems()).firstWhere((i) => i.id == itemId);
      expect(item.currentQty, 0);
      expect(await db.getWastageRecords(), isEmpty);
    });

    test('TC-19: treasury transfer preserves total liquidity and profit',
        () async {
      await db.recordTreasuryFunding(
        entryType: 'OPENING',
        amount: 10000,
      );
      final before = await db.getDashboardSummary();
      await db.recordTreasuryTransfer(
        fromMethod: 'CASH',
        toMethod: 'TRANSFER',
        amount: 3000,
      );
      final after = await db.getDashboardSummary();
      expect(after.cashDrawerBalance, 7000);
      expect(after.transferBalance, 3000);
      expect(after.totalTreasury, before.totalTreasury);
      expect(after.todayNetWorkProfit, before.todayNetWorkProfit);
    });

    test('TC-20: negative stock cost settles from the next purchase', () async {
      final saleId = await db.recordSale(
        itemId: itemId,
        saleType: 'CASH',
        quantity: 2,
        unitPrice: 2000,
      );
      expect((await db.getSales()).single.costStatus, 'PROVISIONAL');
      final supplierId = await db.saveSupplier(name: 'مورد التسوية');
      await db.recordSupplierPurchase(
        supplierId: supplierId,
        itemId: itemId,
        quantity: 10,
        unitPrice: 1000,
        paidAmount: 0,
      );

      final sale = (await db.getSales()).firstWhere((s) => s.id == saleId);
      expect(sale.costStatus, 'FINAL');
      expect(sale.provisionalQuantity, closeTo(0, 0.000001));
      expect(sale.cogsAmount, 2000);
      expect((await db.getDashboardSummary()).todayNetWorkProfit, 2000);
    });

    test('TC-22: failed transaction leaves inventory unchanged', () async {
      final before = (await db.getAllItems()).firstWhere((i) => i.id == itemId);
      expect(
        () => db.recordSale(
          itemId: itemId,
          saleType: 'CREDIT',
          quantity: 1,
          unitPrice: 1000,
        ),
        throwsArgumentError,
      );
      final after = (await db.getAllItems()).firstWhere((i) => i.id == itemId);
      expect(after.currentQty, before.currentQty);
      expect(await db.getSales(), isEmpty);
    });

    test('TC-23: idempotency key prevents duplicate sale and payment',
        () async {
      final first = await db.recordSale(
        itemId: itemId,
        saleType: 'CASH',
        quantity: 1,
        unitPrice: 1000,
        requestKey: 'sale-tap-1',
      );
      final second = await db.recordSale(
        itemId: itemId,
        saleType: 'CASH',
        quantity: 1,
        unitPrice: 1000,
        requestKey: 'sale-tap-1',
      );
      expect(second, first);
      expect((await db.getSales()).length, 1);
      expect(
        (await db.getAllItems()).firstWhere((i) => i.id == itemId).currentQty,
        -1,
      );
    });

    test('TC-27: reset respects item-supplier foreign keys atomically',
        () async {
      final supplierId = await db.saveSupplier(name: 'مورد مرتبط');
      final item = (await db.getAllItems()).firstWhere((i) => i.id == itemId);
      await db.addOrUpdateItem(
        id: itemId,
        name: item.name,
        defaultSupplierId: supplierId,
        unitName: item.unitName,
        defaultSellPrice: item.defaultSellPrice,
      );
      await db.resetTransactionalData();

      expect(await db.getSuppliers(), isEmpty);
      final retained =
          (await db.getAllItems()).firstWhere((i) => i.id == itemId);
      expect(retained.defaultSupplierId, isNull);
      expect(retained.currentQty, 0);
      expect(await db.checkIntegrity(), isTrue);
    });

    test('PIN: legacy plain text upgrades after successful verification',
        () async {
      await db.customUpdate(
        'UPDATE app_settings SET pin_code = ? WHERE id = 1',
        variables: [const Variable<String>('1234')],
      );
      expect(await db.verifyPin('0000'), isFalse);
      expect(await db.verifyPin('1234'), isTrue);
      final stored = (await db.getAppSettings()).pinCode!;
      expect(PinSecurityService.isEncoded(stored), isTrue);
      expect(stored, isNot(contains('1234')));
      expect(await db.verifyPin('1234'), isTrue);
    });
  });

  test('TC-24: v1 file migrates additively without inventing cost', () async {
    final temp = await Directory.systemTemp.createTemp('maqwati_v1_migration_');
    addTearDown(() => temp.delete(recursive: true));
    final file = File(p.join(temp.path, 'legacy.sqlite'));
    final legacy = sqlite.sqlite3.open(file.path);
    legacy.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY, owner_name TEXT NOT NULL, shop_name TEXT NOT NULL,
        phone TEXT NOT NULL, currency TEXT NOT NULL, pin_code TEXT NULL,
        last_backup_at INTEGER NULL, gdrive_email TEXT NULL
      )
    ''');
    legacy.execute(
        "INSERT INTO app_settings VALUES (1, 'قديم', 'قديم', '', 'ر.ي', NULL, NULL, NULL)");
    legacy.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT,
        notes TEXT, balance_lah REAL NOT NULL DEFAULT 0,
        balance_alayh REAL NOT NULL DEFAULT 0, is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    ''');
    legacy.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE,
        default_supplier_id INTEGER NULL REFERENCES suppliers(id),
        unit_name TEXT NOT NULL, current_qty REAL NOT NULL,
        last_buy_price REAL NOT NULL, default_sell_price REAL NOT NULL,
        is_active INTEGER NOT NULL
      )
    ''');
    legacy.execute(
        "INSERT INTO items VALUES (99, 'مخزون قديم', NULL, 'ربطة', 7, 900, 1500, 1)");
    legacy.execute('PRAGMA user_version = 1');
    legacy.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    final item = (await db.getAllItems()).firstWhere((entry) => entry.id == 99);
    expect(item.name, 'مخزون قديم');
    expect(item.currentQty, 7);
    expect(item.costStatus, 'UNKNOWN');
    expect(await db.checkIntegrity(), isTrue);
  });

  test('TC-25/26: backup restores validated data and rejects corruption',
      () async {
    final temp = await Directory.systemTemp.createTemp('maqwati_restore_');
    addTearDown(() => temp.delete(recursive: true));
    final dbFile = File(p.join(temp.path, AppConstants.dbFileName));
    var activeDb = AppDatabase.forTesting(NativeDatabase(dbFile));
    await activeDb.getAppSettings();
    final customerId = await activeDb.saveCustomer(name: 'محفوظ');

    late GoogleDriveBackupService service;
    service = GoogleDriveBackupService(
      activeDb,
      documentsDirectoryOverride: temp,
      onDatabaseReplaced: () async {
        activeDb = AppDatabase.forTesting(NativeDatabase(dbFile));
        await activeDb.getAppSettings();
      },
    );
    final backup = await service.createLocalBackupZip();
    await activeDb.saveCustomer(name: 'بعد النسخة');
    await service.restoreFromZipFile(backup);
    expect((await activeDb.getCustomers()).map((c) => c.id), [customerId]);

    final badArchive = Archive()
      ..addFile(ArchiveFile(
        AppConstants.dbFileName,
        12,
        utf8.encode('not a sqlite'),
      ));
    final badZip = File(p.join(temp.path, 'bad.zip'));
    await badZip.writeAsBytes(ZipEncoder().encode(badArchive)!);
    final before = await activeDb.getCustomers();
    await expectLater(service.restoreFromZipFile(badZip), throwsA(anything));
    expect((await activeDb.getCustomers()).length, before.length);
    expect(await activeDb.checkIntegrity(), isTrue);
    await activeDb.close();
  });
}
