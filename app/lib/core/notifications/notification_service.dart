import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifications système affichées par l'app elle-même.
///
/// Interface, pour que les ViewModels et les tests ne connaissent jamais le
/// plugin. C'est le pendant local de FCM : sur iPhone sans Apple Developer
/// Program le push est impossible (§13), et sur Android elle couvre le cas
/// « app au premier plan », que FCM ne réveille pas.
abstract interface class NotificationService {
  /// Prépare les canaux et demande l'autorisation. Sans effet si déjà fait.
  Future<void> initialize();

  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  /// Appuis sur une notification de l'app, y compris celui qui l'a lancée.
  Stream<void> get opened;
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  var _initialized = false;
  final _opened = StreamController<void>.broadcast();

  @override
  Stream<void> get opened => _opened.stream;

  /// Canal dédié : l'utilisateur peut régler la sonnette sans toucher au reste.
  static const _channelId = 'doorbell';

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        // @mipmap/ic_launcher : pas d'icône monochrome dédiée pour l'instant,
        // c'est une limite connue à corriger avant une vraie mise en ligne.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (_) => _opened.add(null),
    );
    // App fermée puis lancée par un appui sur la notification.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) _opened.add(null);

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    // Créé explicitement, et non à la première notification locale : FCM doit
    // pouvoir y router ses pushs dès le premier démarrage (le manifeste le
    // désigne comme canal par défaut). Sans lui, Android retombe sur
    // `fcm_fallback_notification_channel`, en importance DEFAULT — la
    // notification ne s'afficherait pas en bandeau par-dessus l'écran.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Sonnette',
        description: 'Quelqu\'un sonne au portail',
        importance: Importance.max,
      ),
    );

    // Android 13+ : la permission se demande à l'exécution.
    await android?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true);
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await initialize();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Sonnette',
          channelDescription: 'Quelqu\'un sonne au portail',
          // Max : une sonnerie doit interrompre, c'est tout son intérêt.
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

/// Sur un test widget sans plugin natif, l'implémentation réelle lèverait une
/// MissingPluginException : les tests surchargent ce provider.
/// Volontairement sans effet de bord : c'est le ViewModel de la sonnette qui
/// appelle `initialize()` au démarrage, de façon explicite et testable.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => LocalNotificationService(),
);
