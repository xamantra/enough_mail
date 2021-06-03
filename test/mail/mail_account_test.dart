import 'package:enough_mail/discover/client_config.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:enough_serialization/enough_serialization.dart';
import 'package:test/test.dart';
import 'package:enough_mail/mail/mail_account.dart';

void main() {
  void _compareAfterJsonSerialization(MailAccount original) {
    var text = Serializer().serialize(original);
    //print(text);
    var copy = MailAccount();
    Serializer().deserialize(text, copy);
    //print('copy==original: ${copy == original}');
    expect(copy.incoming?.serverConfig, original.incoming?.serverConfig);
    expect(copy.incoming, original.incoming);
    expect(copy.outgoing, original.outgoing);
    expect(copy, original);
  }

  group('Serialize', () {
    test('serialize account 1', () {
      var original = MailAccount()..email = 'test@domain.com';
      _compareAfterJsonSerialization(original);
    });

    test('serialize account 2', () {
      var original = MailAccount()
        ..email = 'test@domain.com'
        ..name = 'A name with "quotes"'
        ..outgoingClientDomain = 'outgoing.com'
        ..supportsPlusAliases = true;
      _compareAfterJsonSerialization(original);
    });

    test('serialize account 3', () {
      var original = MailAccount()
        ..email = 'test@domain.com'
        ..userName = 'tester test'
        ..name = 'A name with "quotes"'
        ..outgoingClientDomain = 'outgoing.com'
        ..incoming = MailServerConfig(
            serverConfig: ServerConfig(
                type: ServerType.imap,
                hostname: 'imap.domain.com',
                port: 993,
                socketType: SocketType.ssl,
                authentication: Authentication.plain,
                usernameType: UsernameType.emailAddress),
            authentication: PlainAuthentication('user@domain.com', 'secret'),
            serverCapabilities: [Capability('IMAP4')],
            pathSeparator: '/')
        ..outgoing = MailServerConfig(
            serverConfig: ServerConfig(
                type: ServerType.smtp,
                hostname: 'smtp.domain.com',
                port: 993,
                socketType: SocketType.ssl,
                authentication: Authentication.plain,
                usernameType: UsernameType.emailAddress),
            authentication: PlainAuthentication('user@domain.com', 'secret'))
        ..supportsPlusAliases = true
        ..aliases = [MailAddress('just tester', 'alias@domain.com')];
      _compareAfterJsonSerialization(original);
    });

    test('serialize list of accounts', () {
      var accounts = [
        MailAccount()
          ..email = 'test@domain.com'
          ..name = 'A name with "quotes"'
          ..outgoingClientDomain = 'outgoing.com'
          ..incoming = MailServerConfig(
              serverConfig: ServerConfig(
                  type: ServerType.imap,
                  hostname: 'imap.domain.com',
                  port: 993,
                  socketType: SocketType.ssl,
                  authentication: Authentication.plain,
                  usernameType: UsernameType.emailAddress),
              authentication: PlainAuthentication('user@domain.com', 'secret'),
              serverCapabilities: [Capability('IMAP4')],
              pathSeparator: '/')
          ..outgoing = MailServerConfig(
              serverConfig: ServerConfig(
                  type: ServerType.smtp,
                  hostname: 'smtp.domain.com',
                  port: 993,
                  socketType: SocketType.ssl,
                  authentication: Authentication.plain,
                  usernameType: UsernameType.emailAddress),
              authentication: PlainAuthentication('user@domain.com', 'secret')),
        MailAccount()
          ..email = 'test2@domain2.com'
          ..name = 'my second account'
          ..outgoingClientDomain = 'outdomain.com'
          ..incoming = MailServerConfig(
              serverConfig: ServerConfig(
                  type: ServerType.imap,
                  hostname: 'imap.domain2.com',
                  port: 993,
                  socketType: SocketType.ssl,
                  authentication: Authentication.plain,
                  usernameType: UsernameType.emailAddress),
              authentication:
                  PlainAuthentication('user2@domain2.com', 'verysecret'),
              serverCapabilities: [Capability('IMAP4'), Capability('IDLE')],
              pathSeparator: '/')
          ..outgoing = MailServerConfig(
              serverConfig: ServerConfig(
                  type: ServerType.smtp,
                  hostname: 'smtp.domain2.com',
                  port: 993,
                  socketType: SocketType.ssl,
                  authentication: Authentication.plain,
                  usernameType: UsernameType.emailAddress),
              authentication:
                  PlainAuthentication('user2@domain2.com', 'topsecret')),
      ];
      final serializer = Serializer();
      var jsonText = serializer.serializeList(accounts);
      var parsedAccounts = <MailAccount>[];
      serializer.deserializeList(
          jsonText, parsedAccounts, (map) => MailAccount());

      expect(parsedAccounts.length, accounts.length);
      for (var i = 0; i < accounts.length; i++) {
        final original = accounts[i];
        final copy = parsedAccounts[i];
        expect(copy, original);
      }
    });
  });
}
