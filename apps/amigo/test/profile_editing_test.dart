import 'dart:convert';
import 'dart:io';

import 'package:amigo/features/authentication/account_repository.dart';
import 'package:amigo/features/profile/profile_photo_screen.dart';
import 'package:amigo/features/profile/profile_repository.dart';
import 'package:amigo/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _originalAbout =
    'I grew up exploring our local markets and beaches with my family. '
    'I enjoy finding quiet places for coffee, sharing neighborhood stories, '
    'and helping visitors feel comfortable exploring at their own pace.';
const _newAbout =
    'I enjoy taking visitors through neighborhood markets, local cafes, and '
    'small museums. We can explore on foot, stop at interesting places, '
    'and make time for coffee or a snack whenever you would like.';
const _imagePath = 'assets/figma/account/location_map.png';
const _picker = MethodChannel('plugins.flutter.io/image_picker');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'profile fields open separately and show the saved database row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _ProfileApi();
      final client = (await tester.runAsync(api.connect))!;
      var refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AmigoProfileScreen(
            account: AmigoAccountRepository(client),
            onProfileChanged: () => refreshes++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> tapVisible(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var canceledPicks = 0;
      messenger.setMockMethodCallHandler(_picker, (call) async {
        expect(call.method, 'pickImage');
        canceledPicks++;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_picker, null));
      await tester.tap(
        find.ancestor(of: find.text('A'), matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit profile photo'));
      await tester.pumpAndSettle();
      expect(canceledPicks, 2);
      expect(find.text('Edit profile photo'), findsNothing);
      expect(api.uploadPaths, isEmpty);

      final save = find.widgetWithText(FilledButton, 'Save');
      await tapVisible(find.text('Interests'));
      final photography = find.widgetWithText(FilterChip, 'Photography');
      expect(find.text('Edit interests'), findsOneWidget);
      expect(tester.widget<FilterChip>(photography).selected, isTrue);
      expect(find.byType(TextFormField), findsNothing);
      await tapVisible(find.widgetWithText(FilterChip, 'Local Culture'));
      await tapVisible(save);
      expect(api.updates.single, {
        'interests': ['Photography', 'Local Culture'],
      });
      expect(find.text('Photography, Local Culture'), findsOneWidget);

      await tapVisible(find.text('About you'));
      expect(find.text('Edit about you'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      final field = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(field).controller!.text,
        _originalAbout,
      );
      await tester.enterText(field, _newAbout);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tapVisible(save);
      expect(api.updates.last, {'description': _newAbout});
      expect(find.text(_newAbout), findsOneWidget);

      await tapVisible(find.text('Hourly rate'));
      expect(find.text('Edit hourly rate'), findsOneWidget);
      expect(tester.widget<TextFormField>(field).controller!.text, '500.00');
      await tester.enterText(field, '699.50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tapVisible(find.text('Cancel'));
      expect(api.updates, hasLength(2));
      expect(find.text('₱500.00 per hour'), findsOneWidget);
      await tapVisible(find.text('Hourly rate'));
      await tester.enterText(field, '199.99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tapVisible(save);
      expect(find.textContaining('Enter ₱200'), findsOneWidget);
      expect(api.updates, hasLength(2));
      await tester.enterText(field, '725.50');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tapVisible(save);
      expect(api.updates.last, {'rate_centavos': 72550});
      expect(find.text('₱725.50 per hour'), findsOneWidget);
      expect(api.profile['description'], _newAbout);
      expect(api.profile['area'], 'Batangas');
      expect(refreshes, 3);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(client.dispose);
    },
  );

  test(
    'native picker returns the selected image and handles cancellation',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var pickerCalls = 0;
      final file = File(_imagePath).absolute;
      messenger.setMockMethodCallHandler(_picker, (call) async {
        expect(call.method, 'pickImage');
        expect(call.arguments['source'], ImageSource.gallery.index);
        return pickerCalls++ == 0 ? null : file.path;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_picker, null));
      expect(await pickAmigoProfilePhoto(), isNull);
      final photo = await pickAmigoProfilePhoto();
      expect(photo?.mime, 'image/png');
      expect(photo?.bytes, await file.readAsBytes());
      expect(pickerCalls, 2);
    },
  );

  testWidgets('photo preview retries upload and preserves the uploaded path', (
    tester,
  ) async {
    final api = _ProfileApi()..failPhoto = true;
    final client = (await tester.runAsync(api.connect))!;
    final bytes = (await tester.runAsync(
      () => File(_imagePath).readAsBytes(),
    ))!;
    Map<String, dynamic>? updated;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                updated = await Navigator.of(context)
                    .push<Map<String, dynamic>>(
                      MaterialPageRoute(
                        builder: (_) => AmigoProfilePhotoScreen(
                          repository: AmigoProfileRepository(client),
                          photo: (bytes: bytes, mime: 'image/png'),
                        ),
                      ),
                    );
              },
              child: const Text('Open photo preview'),
            ),
          ),
        ),
      ),
    );

    await tester.runAsync(
      () => precacheImage(
        MemoryImage(bytes),
        tester.element(find.text('Open photo preview')),
      ),
    );

    Future<void> tap(Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    final open = find.text('Open photo preview');
    final save = find.widgetWithText(FilledButton, 'Save photo');
    await tap(open);
    expect(find.byType(Image), findsOneWidget);
    expect(api.uploadPaths, isEmpty);
    await tap(find.text('Cancel'));
    expect(updated, isNull);
    expect(api.uploadPaths, isEmpty);

    await tap(open);
    await tap(save);
    expect(find.textContaining('Could not upload your photo'), findsOneWidget);
    expect(api.updates, isEmpty);
    await tap(save);
    expect(find.textContaining('The photo uploaded'), findsOneWidget);
    expect(api.uploadPaths, hasLength(2));
    expect(api.uploadPaths.first, api.uploadPaths.last);
    await tap(save);
    expect(api.uploadPaths, hasLength(2));
    expect(api.updates, hasLength(2));
    expect(api.updates.first, api.updates.last);
    expect(updated?['photo_path'], api.uploadPaths.last);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(client.dispose);
  });
}

class _ProfileApi {
  final profile = <String, dynamic>{
    'id': 'amigo-profile',
    'display_name': 'Avery Example',
    'description': _originalAbout,
    'verified': true,
    'interests': ['Photography'],
    'area': 'Batangas',
    'rate_centavos': 50000,
  };
  final updates = <Map<String, dynamic>>[];
  final uploadPaths = <String>[];
  bool failPhoto = false;

  Future<SupabaseClient> connect() async {
    final client = SupabaseClient(
      'https://gomigo.example',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_handle),
    );
    final claims = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'sub': 'test-amigo',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60,
        }),
      ),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJub25lIn0.$claims.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'user': {'id': 'test-amigo'},
      }),
    );
    return client;
  }

  Future<http.Response> _handle(http.Request request) async {
    http.Response send(Object data, [int status = 200]) => http.Response(
      jsonEncode(data),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );

    final segments = request.url.pathSegments;
    if (segments.length > 4 && segments[3] == 'amigo-photos') {
      final path = segments.skip(4).join('/');
      uploadPaths.add(path);
      if (failPhoto && uploadPaths.length == 1) {
        return send({'message': 'Upload failed'}, 403);
      }
      return send({'Key': 'amigo-photos/$path'});
    }
    return switch (segments.last) {
      'profiles' => send({
        'display_name': profile['display_name'],
        'role': 'amigo',
      }),
      'my_amigo_id' => send(profile['id']!),
      'amigo_profiles' => send(profile),
      'update_amigo_profile' => _update(request, send),
      _ => throw StateError('Unexpected request: ${request.url.path}'),
    };
  }

  http.Response _update(
    http.Request request,
    http.Response Function(Object data, [int status]) send,
  ) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final changes = body['p_changes'] as Map<String, dynamic>;
    updates.add(changes);
    if (failPhoto && updates.length == 1) {
      return send({'message': 'Save failed'}, 400);
    }
    profile.addAll(changes);
    return send(profile);
  }
}
