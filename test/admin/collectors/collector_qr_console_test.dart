import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:project2/admin/access/admin_session_gateway.dart';
import 'package:project2/admin/collectors/collector_management_page.dart';
import 'package:project2/admin/local_api_visit_repository.dart';
import 'package:project2/collector_auth/collector_qr_payload.dart';
import 'package:project2/domain/authenticated_user.dart';

void main() {
  const admin = AuthenticatedUser(id: 'admin.test', role: UserRole.admin);
  const secret = 'synthetic-collector-key-0123456789012345';
  for (final scenario in ['valid', 'disabled', 'error']) {
    testWidgets('QR console $scenario', (tester) async {
      var qrRequests = 0;
      final repo = LocalApiVisitRepository(
        apiKey: 'test-admin-key',
        client: MockClient((request) async {
          expect(request.headers['x-local-sync-key'], 'test-admin-key');
          if (request.url.path.endsWith('/qr')) {
            qrRequests++;
            if (scenario == 'error')
              return http.Response('sensitive-error-$secret', 403);
            return http.Response(
              CollectorQrPayload.generateJson(
                collectorNumber: 1,
                collectorKey: secret,
              ),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'collectors': [
                {
                  'code': 'C001',
                  'status': scenario == 'disabled' ? 'disabled' : 'active',
                  'createdAt': '2026-09-26T00:00:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CollectorManagementPage(
            sessionGateway: const InMemoryAdminSessionGateway(admin),
            collectorGateway: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (scenario == 'disabled') {
        expect(find.text('Generate sign-in QR'), findsNothing);
        expect(qrRequests, 0);
        return;
      }
      await tester.tap(find.text('Generate sign-in QR'));
      await tester.pumpAndSettle();
      expect(qrRequests, 1);
      expect(find.textContaining(secret), findsNothing);
      if (scenario == 'error') {
        expect(find.byType(QrImageView), findsNothing);
        expect(find.textContaining('could not be generated'), findsOneWidget);
      } else {
        expect(find.byType(QrImageView), findsOneWidget);
        final qr = tester.widget<QrImageView>(find.byType(QrImageView));
        expect(qr.semanticsLabel, 'Private collector sign-in QR');
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(QrImageView), findsNothing);
      }
    });
  }
}
