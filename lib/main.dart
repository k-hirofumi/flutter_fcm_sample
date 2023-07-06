import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final testProvider = StateProvider<String>((ref) => 'init');
final badgeCountProvider = StateProvider<int>((ref) => 0);

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Handling a background message ${message.messageId}');

  ///////
  //メインisolateにメッセージを送る
  ///////
  // "port_send_port"という名前で登録したSendPortを取得
  SendPort? mainSendPort = IsolateNameServer.lookupPortByName('port_send_port');
  // 取得したSendPortを使ってメッセージを送る
  mainSendPort?.send('background message');
}

/// 1以上の数値を渡すことでホーム画面のアイコンにバッジを表示する
void setIconBadge({int? number}) async {
  print('setIconBadge');
  // バッジ表示機能に対応している場合のみ、バッジの数字を更新する
  if (await FlutterAppBadger.isAppBadgeSupported()) {
    FlutterAppBadger.updateBadgeCount(
        number ?? 0); // <-引数の`number`が`null`だった場合は`0`
  }
}

void main() async {
  //firebaseの初期化
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('Firebase initializeApp complete');

  /////
  ///　アプリがバックグラウンド処理中にメッセージを受け取った場合の処理
  /// iosでonBackgroundMessageは通常では実行されない、バックエンド側のpayloadにcontent-available: 1を含める必要がある
  /// fcmのテスト送信ではペイロードの追加はできないので、バックエンドを構築してテストする必要がある
  /////
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // FCM の通知権限リクエスト
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );
  final token = await messaging
      .getToken(); //トークンを取得しfirebaseに登録(FCMとの連携が正常に動いていない場合は取得できない)
  print('token');
  print(token);

  setIconBadge(number: 0);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    //////////
    //　別isolateからのメッセージを受け取る
    //////////
    ReceivePort port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, 'port_send_port');
    port.listen((dynamic data) {
      print('Received: $data');
      // ここで受け取ったメッセージに対する処理を行う
      ref.watch(testProvider.notifier).state = data;
      //アプリのバッジ（未読数）を更新
      final bacgeCount = ++ref.watch(badgeCountProvider.notifier).state;
      setIconBadge(number: bacgeCount);
    });

    //////////
    //　フォアグラウンドメッセージのハンドリング
    //////////
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('Foreground message received: ${message.messageId}');
      // ここでメッセージをハンドルします。
    });

    //////////
    //　プッシュ通知をタップした際のハンドリング
    //////////
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      print(
          'A new onMessageOpenedApp event was published: ${message.messageId}');
      // ここでメッセージをハンドルします。
    });

    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends ConsumerStatefulWidget {
  const MyHomePage({super.key});

  @override
  ConsumerState<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<MyHomePage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // フォアグラウンドになった時
      print('App is in Foreground');
      setIconBadge(number: 0);
    } else if (state == AppLifecycleState.paused) {
      // バックグラウンドになった時
      print('App is in Background');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('test'),
      ),
      body: Center(
        child: Column(children: [
          Text('test'),
          Text(ref.watch(testProvider)),
        ]),
      ),
    );
  }
}
