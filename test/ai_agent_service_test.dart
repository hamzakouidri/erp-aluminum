import 'dart:convert';

import 'package:database_data/services/ai_agent_service.dart';
import 'package:database_data/services/gemini_gateway.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _modelTurn(List<Map<String, dynamic>> parts) => {
  'candidates': [
    {
      'content': {'role': 'model', 'parts': parts},
    },
  ],
};

void main() {
  test('the strongest chat model is preferred', () {
    final names =
        [
          'gemini-2.5-flash',
          'gemini-3-pro-preview',
          'gemini-2.5-pro',
          'gemini-3-flash',
          'gemini-2.5-flash-lite',
        ]..sort(
          (a, b) => AiAgentService.modelRank(
            b,
          ).compareTo(AiAgentService.modelRank(a)),
        );
    expect(names.first, 'gemini-3-pro-preview');
    expect(names.last, 'gemini-2.5-flash-lite');
    expect(AiAgentService.isConversationModel('gemini-2.5-flash-image'), false);
    expect(AiAgentService.isConversationModel('gemini-embedding-001'), false);
    expect(AiAgentService.isConversationModel('gemini-2.5-pro'), true);
  });

  test(
    'the agent calls tools, returns their results and asks before a change',
    () async {
      final requests = <Map<String, dynamic>>[];
      var turn = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return _json({
            'models': [
              {
                'name': 'models/gemini-2.5-flash',
                'supportedGenerationMethods': ['generateContent'],
              },
              {
                'name': 'models/gemini-2.5-pro',
                'supportedGenerationMethods': ['generateContent'],
              },
              {
                'name': 'models/text-embedding-004',
                'supportedGenerationMethods': ['embedContent'],
              },
            ],
          });
        }
        expect(request.url.path, contains('gemini-2.5-pro'));
        // The key travels in a header, never in the address.
        expect(request.url.query, isNot(contains('key')));
        expect(request.headers['x-goog-api-key'], 'k');
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        turn++;
        if (turn == 1) {
          return _json(
            _modelTurn([
              {
                'functionCall': {
                  'name': 'update_order_status',
                  'args': {'order_id': 7, 'status': 'Done'},
                },
                'thoughtSignature': 'sig-1',
              },
            ]),
          );
        }
        if (turn == 2) {
          return _json(
            _modelTurn([
              {
                'functionCall': {
                  'name': 'open_screen',
                  'args': {'screen': 'orders'},
                },
              },
            ]),
          );
        }
        return _json(
          _modelTurn([
            {'text': 'لم أغيّر الحالة لأنك ألغيت. فتحت لك الطلبيات.'},
          ]),
        );
      });

      final confirmations = <String>[];
      final agent = AiAgentService(
        gateway: GeminiGateway(personalKey: 'k', client: client),
      );
      final result = await agent.run(
        userText: 'اجعل الطلبية 7 منتهية',
        history: const [
          {'role': 'model', 'content': 'مرحبا'},
          {'role': 'user', 'content': 'سؤال سابق'},
          {'role': 'model', 'content': 'جواب سابق'},
        ],
        language: AppLanguage.arabic,
        permissions: const AiAgentPermissions(
          viewOrders: true,
          changeOrderStatus: true,
        ),
        confirm: (title, details) async {
          confirmations.add(details);
          return false;
        },
      );

      expect(result.isError, isFalse);
      expect(result.model, 'gemini-2.5-pro');
      expect(result.navigateTo, 'orders');
      expect(result.text, contains('ألغيت'));
      expect(confirmations.single, contains('Done'));

      // Only the user's tools are offered.
      final declared = [
        for (final f
            in (requests.first['tools'] as List).first['functionDeclarations']
                as List)
          f['name'],
      ];
      expect(declared, containsAll(['search_orders', 'update_order_status']));
      expect(declared, isNot(contains('record_client_payment')));
      expect(declared, isNot(contains('search_stock')));

      // History starts with the user and the new message comes last.
      final first = requests.first['contents'] as List;
      expect(first.first['role'], 'user');
      expect(first.last['parts'].first['text'], 'اجعل الطلبية 7 منتهية');

      // The model turn is echoed with its signature, then the refusal.
      final second = requests[1]['contents'] as List;
      expect(
        second[second.length - 2]['parts'].first['thoughtSignature'],
        'sig-1',
      );
      expect(
        second.last['parts'].first['functionResponse']['response']['status'],
        'cancelled by the user',
      );
    },
  );

  test('a daily limit stops the agent with a clear message', () async {
    final client = MockClient(
      (request) async => request.method == 'GET'
          ? _json({'models': []})
          : http.Response('{"error":"Daily AI limit reached"}', 429),
    );
    final result =
        await AiAgentService(
          gateway: GeminiGateway(personalKey: 'k', client: client),
        ).run(
          userText: 'hi',
          language: AppLanguage.english,
          permissions: const AiAgentPermissions(),
          confirm: (_, _) async => true,
        );
    expect(result.isError, isTrue);
    expect(result.text, contains('daily limit'));
  });
}
