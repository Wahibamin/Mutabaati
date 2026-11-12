import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqwati/core/widgets/custom_numeric_keypad.dart';
import 'package:maqwati/data/local_db/app_database.dart';
import 'package:maqwati/features/customers/presentation/customers_screen.dart';
import 'package:maqwati/features/home/presentation/home_screen.dart';
import 'package:maqwati/features/home/presentation/settings_and_backup_screen.dart';
import 'package:maqwati/features/home/presentation/user_info_screen.dart';
import 'package:maqwati/features/sales/presentation/sales_screen.dart';
import 'package:maqwati/features/suppliers/presentation/suppliers_screen.dart';

/// مساعدة: تشغيل الشاشة وانتظار تحديث البيانات.
/// نستخدم runAsync لأن الشاشات تستخدم StreamProviders مع SQLite (I/O حقيقي).
/// pump() وحدها لا تكفي مع I/O operations حقيقية - تحتاج runAsync لتشغيلها.
Future<void> pumpScreenAndRender(WidgetTester tester) async {
  // pumpWidget() أُطلق بالفعل. نسمح للـ async I/O بالانتهاء
  await tester.runAsync(() async {
    await Future.delayed(const Duration(milliseconds: 500));
  });
  // إطار لمعالجة نتائج الـ Streams
  await tester.pump();
  await tester.runAsync(() async {
    await Future.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.getAppSettings();

    // إدراج بيانات اختبارية لتمثيل المحتوى الحقيقي بدقة
    final items = await db.getAllItems();
    final firstItem = items.first;

    final supplierId = await db.saveSupplier(
      name: 'صالح علي المسوق (مورد رئيسي ذو اسم طويل)',
      phone: '777123456',
      notes: 'منطقة الحداء - قات عنسي ممتاز',
    );

    final customerId = await db.saveCustomer(
      name: 'الزبون عبد الرحمن محمد الشاوش (اسم طويل للتحقق من الاتساع)',
      phone: '777987654',
      creditLimit: 50000,
      notes: 'زبون دائم',
    );

    await db.recordSupplierPurchase(
      supplierId: supplierId,
      itemId: firstItem.id,
      quantity: 15,
      unitPrice: 4000,
      paidAmount: 20000,
      paymentMethod: 'CASH',
    );

    await db.recordSale(
      itemId: firstItem.id,
      saleType: 'CREDIT',
      customerId: customerId,
      quantity: 2,
      unitPrice: 6500,
      paidAmount: 3000,
      paymentMethod: 'CASH',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildTestableWidget({
    required Widget child,
    required Size size,
    required double textScale,
    ProviderContainer? container,
  }) {
    final root = MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
      ),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: root,
      );
    }

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: root,
    );
  }

  // أحجام الشاشات الممثلة وفق جدول المتطلبات (القسم 8)
  final screenWidths = [
    320.0, // هاتف صغير (320dp)
    360.0, // هاتف صغير شائع (360dp - مكان ظهور المشاكل الأصلية)
    393.0, // هاتف متوسط (393dp)
    412.0, // هاتف متوسط أكبر (412dp)
    480.0, // جهاز بعرض أكبر (480dp)
    600.0, // هاتف كبير / نافذة متعددة (600dp)
    840.0, // تابلت (840dp)
  ];

  // مستويات تكبير الخط (100% و 120% و 150% و 200%)
  final textScales = [1.0, 1.2, 1.5, 2.0];

  group('HomeScreen Responsive & Overflow Tests', () {
    for (final width in screenWidths) {
      for (final scale in textScales) {
        testWidgets(
          'HomeScreen renders without overflow at ${width.toInt()}dp with textScale ${(scale * 100).toInt()}%',
          (tester) async {
            final container = ProviderContainer(
              overrides: [
                appDatabaseProvider.overrideWithValue(db),
              ],
            );
            addTearDown(() async {
              // Unmount first so Riverpod cancels HomeScreen's stream
              // subscriptions before their container and database are closed.
              await tester.pumpWidget(const SizedBox.shrink());
              container.dispose();
            });

            tester.view.physicalSize = Size(width * 2, 800 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);

            FlutterErrorDetails? overflowDetails;
            final prevOnError = FlutterError.onError;
            FlutterError.onError = (details) {
              if (details.toString().contains('overflowed')) {
                overflowDetails = details;
              }
              prevOnError?.call(details);
            };
            addTearDown(() => FlutterError.onError = prevOnError);

            await tester.pumpWidget(
              buildTestableWidget(
                container: container,
                child: const HomeScreen(),
                size: Size(width, 800),
                textScale: scale,
              ),
            );
            // استخدام pumpScreenAndRender بدلاً من pumpAndSettle لأن HomeScreen تستخدم StreamProviders
            await pumpScreenAndRender(tester);

            final err = tester.takeException();
            if (overflowDetails != null) {
              // ignore: avoid_print
              print('=== OVERFLOW DETECTED ===');
              // ignore: avoid_print
              print(overflowDetails!.toString());
              final collector = overflowDetails!.informationCollector;
              if (collector != null) {
                for (final node in collector()) {
                  // ignore: avoid_print
                  print(node.toStringDeep());
                }
              }
              // ignore: avoid_print
              print('=== END OVERFLOW ===');
            }
            expect(err, isNull);
          },
        );
      }
    }
  });

  group('SuppliersScreen Responsive & Overflow Tests', () {
    for (final width in [320.0, 360.0, 393.0, 412.0, 840.0]) {
      for (final scale in [1.0, 1.2, 1.5, 2.0]) {
        testWidgets(
          'SuppliersScreen renders without overflow at ${width.toInt()}dp with textScale ${(scale * 100).toInt()}%',
          (tester) async {
            tester.view.physicalSize = Size(width * 2, 800 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              buildTestableWidget(
                child: const SuppliersScreen(),
                size: Size(width, 800),
                textScale: scale,
              ),
            );
            // استخدام pumpScreenAndRender لأن SuppliersScreen تستخدم StreamProviders
            await pumpScreenAndRender(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('CustomersScreen Responsive & Overflow Tests', () {
    for (final width in [320.0, 360.0, 393.0, 412.0, 840.0]) {
      for (final scale in [1.0, 1.2, 1.5, 2.0]) {
        testWidgets(
          'CustomersScreen renders without overflow at ${width.toInt()}dp with textScale ${(scale * 100).toInt()}%',
          (tester) async {
            tester.view.physicalSize = Size(width * 2, 800 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              buildTestableWidget(
                child: const CustomersScreen(),
                size: Size(width, 800),
                textScale: scale,
              ),
            );
            // استخدام pumpScreenAndRender لأن CustomersScreen تستخدم StreamProviders
            await pumpScreenAndRender(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('SalesScreen Responsive & Overflow Tests', () {
    for (final width in [320.0, 360.0, 393.0, 412.0, 840.0]) {
      for (final scale in [1.0, 1.2, 1.5, 2.0]) {
        testWidgets(
          'SalesScreen renders without overflow at ${width.toInt()}dp with textScale ${(scale * 100).toInt()}%',
          (tester) async {
            tester.view.physicalSize = Size(width * 2, 800 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              buildTestableWidget(
                child: const SalesScreen(),
                size: Size(width, 800),
                textScale: scale,
              ),
            );
            // استخدام pumpScreenAndRender لأن SalesScreen تستخدم StreamProviders
            await pumpScreenAndRender(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('SettingsAndBackupScreen Responsive & Overflow Tests', () {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'SettingsAndBackupScreen renders without overflow at ${width.toInt()}dp with textScale ${(scale * 100).toInt()}%',
          (tester) async {
            tester.view.physicalSize = Size(width * 2, 800 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              buildTestableWidget(
                child: const SettingsAndBackupScreen(),
                size: Size(width, 800),
                textScale: scale,
              ),
            );
            // استخدام pumpScreenAndRender لأن SettingsAndBackupScreen تستخدم StreamProviders
            await pumpScreenAndRender(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('CustomNumericKeypad Responsive & Overflow Tests', () {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'CustomNumericKeypad renders without overflow at ${width.toInt()}dp with textScale ${(scale * 100).toInt()}%',
          (tester) async {
            tester.view.physicalSize = Size(width * 2, 700 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              buildTestableWidget(
                child: Scaffold(
                  body: CustomNumericKeypad(
                    title:
                        'المدفوع للمورد الآن (0 إذا كان الشراء بالآجل كاملاً)',
                    initialValue: 15000,
                    showQuickAmounts: true,
                    onConfirmed: (_) {},
                  ),
                ),
                size: Size(width, 700),
                textScale: scale,
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('UserInfoScreen Responsive & Overflow Tests', () {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets(
          'UserInfoScreen renders without overflow at ${width.toInt()}dp with textScale ${(scale * 100).toInt()}%',
          (tester) async {
            tester.view.physicalSize = Size(width * 2, 800 * 2);
            tester.view.devicePixelRatio = 2.0;
            addTearDown(tester.view.resetPhysicalSize);

            await tester.pumpWidget(
              buildTestableWidget(
                child: const UserInfoScreen(),
                size: Size(width, 800),
                textScale: scale,
              ),
            );
            // استخدام pumpScreenAndRender لأن UserInfoScreen تستخدم StreamProviders
            await pumpScreenAndRender(tester);

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
