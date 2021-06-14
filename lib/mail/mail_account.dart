import 'package:enough_mail/discover/client_config.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:enough_serialization/enough_serialization.dart';

import 'mail_authentication.dart';

/// Contains information about a single mail account
class MailAccount extends SerializableObject {
  /// The name of the account
  String get name => attributes['name'];
  set name(String value) => attributes['name'] = value;

  /// The associated name of the user such as `user@domain.com`
  String get userName => attributes['userName'];
  set userName(String value) => attributes['userName'] = value;

  /// The email address of the user
  String get email => attributes['email'];
  set email(String value) => attributes['email'] = value;

  /// Incoming mail settings
  MailServerConfig get incoming => attributes['incoming'];
  set incoming(MailServerConfig value) => attributes['incoming'] = value;

  /// Outgoing mail settings
  MailServerConfig get outgoing => attributes['outgoing'];
  set outgoing(MailServerConfig value) => attributes['outgoing'] = value;

  /// The domain that is reported to the outgoing SMTP service
  String get outgoingClientDomain => attributes['outgoingClientDomain'] ?? 'enough.de';
  set outgoingClientDomain(String value) => attributes['outgoingClientDomain'] = value;

  /// Convenience getter for the from MailAddress
  MailAddress get fromAddress => MailAddress(userName, email);

  /// Optional list of associated aliases
  List<MailAddress> get aliases => attributes['aliases'];
  set aliases(List<MailAddress> value) => attributes['aliases'] = value;

  /// Optional indicator if the mail service supports + based aliases, e.g. `user+alias@domain.com`.
  bool get supportsPlusAliases => attributes['supportsPlusAliases'] ?? false;
  set supportsPlusAliases(bool value) => attributes['supportsPlusAliases'] = value;

  /// Checks if this account has an attribute with the specified name
  bool hasAttribute(String name) => attributes.containsKey(name);

  MailAccount() {
    objectCreators['incoming'] = (map) => MailServerConfig();
    objectCreators['outgoing'] = (map) => MailServerConfig();
    objectCreators['aliases'] = (map) => <MailAddress>[];
    objectCreators['aliases.value'] = (map) => MailAddress.empty();
  }

  /// Creates a mail account with a plain authentication for the preferred incoming and preferred outgoing server.
  static MailAccount fromDiscoveredSettings(String name, String email, String password, ClientConfig config, {String userName, String outgoingClientDomain}) {
    userName ??= config.preferredIncomingServer.getUserName(email);
    userName ??= email;
    var auth = PlainAuthentication(userName, password);
    var incoming = MailServerConfig()
      ..authentication = auth
      ..serverConfig = config.preferredIncomingImapServer;
    var outgoing = MailServerConfig()
      ..authentication = auth
      ..serverConfig = config.preferredOutgoingServer;
    var account = MailAccount()
      ..name = name
      ..email = email
      ..incoming = incoming
      ..outgoing = outgoing;
    if (outgoingClientDomain != null) {
      account.outgoingClientDomain = outgoingClientDomain;
    }
    return account;
  }

  /// Creates a mail account from manual settings with a simple user-name/password authentication.
  ///
  /// You need to specify the account [name], the associated [email], the [incomingHost], [outgoingHost] and [password].
  /// When the [userName] is different from the email, it must also be specified.
  /// You should specify the [outgoingClientDomain] for sending messages, this defaults to `enough.de`.
  /// The [incomingType] defaults to [ServerType.imap], the [incomingPort] to `993` and the [incomingSocketType] to [SocketType.ssl].
  /// The [outgoingType] defaults to [ServerType.smtp], the [outgoingPort] to `465` and the [outgoingSocketType] to [SocketType.ssl].
  static MailAccount fromManualSettings(
    String name,
    String email,
    String incomingHost,
    String outgoingHost,
    String password, {
    ServerType incomingType = ServerType.imap,
    ServerType outgoingType = ServerType.smtp,
    String userName,
    String outgoingClientDomain,
    incomingPort = 993,
    outgoingPort = 465,
    SocketType incomingSocketType = SocketType.ssl,
    SocketType outgoingSocketType = SocketType.ssl,
  }) {
    final auth = PlainAuthentication(userName ?? email, password);
    return fromManualSettingsWithAuth(name, email, incomingHost, outgoingHost, auth, incomingType: incomingType, outgoingType: outgoingType, outgoingClientDomain: outgoingClientDomain);
  }

  /// Creates a mail account from manual settings with the specified [auth]entication.
  ///
  /// You need to specify the account [name], the associated [email], the [incomingHost], [outgoingHost] and [auth].
  /// You can specify a different authentication for the outgoing server using the [outgoingAuth] parameter.
  /// You should specify the [outgoingClientDomain] for sending messages, this defaults to `enough.de`.
  /// The [incomingType] defaults to [ServerType.imap], the [incomingPort] to `993` and the [incomingSocketType] to [SocketType.ssl].
  /// The [outgoingType] defaults to [ServerType.smtp], the [outgoingPort] to `465` and the [outgoingSocketType] to [SocketType.ssl].
  static MailAccount fromManualSettingsWithAuth(
    String name,
    String email,
    String incomingHost,
    String outgoingHost,
    MailAuthentication auth, {
    ServerType incomingType = ServerType.imap,
    ServerType outgoingType = ServerType.smtp,
    MailAuthentication outgoingAuth,
    String outgoingClientDomain = 'enough.de',
    incomingPort = 993,
    outgoingPort = 465,
    SocketType incomingSocketType = SocketType.ssl,
    SocketType outgoingSocketType = SocketType.ssl,
  }) {
    final incoming = MailServerConfig()
      ..authentication = auth
      ..serverConfig = ServerConfig(
        type: incomingType,
        hostname: incomingHost,
        port: incomingPort,
        socketType: incomingSocketType,
      );
    final outgoing = MailServerConfig()
      ..authentication = outgoingAuth ?? auth
      ..serverConfig = ServerConfig(
        type: outgoingType,
        hostname: outgoingHost,
        port: outgoingPort,
        socketType: outgoingSocketType,
      );
    final account = MailAccount()
      ..name = name
      ..email = email
      ..incoming = incoming
      ..outgoing = outgoing
      ..outgoingClientDomain = outgoingClientDomain;
    return account;
  }

  @override
  bool operator ==(o) => o is MailAccount && o.name == name && o.userName == userName && o.email == email && o.outgoingClientDomain == outgoingClientDomain && o.incoming == incoming && o.outgoing == outgoing && o.supportsPlusAliases == supportsPlusAliases && o.aliases?.length == aliases?.length && o.attributes?.length == attributes?.length;

  @override
  String toString() {
    return Serializer().serialize(this);
  }
}

/// Configuration of an mail service
class MailServerConfig extends SerializableObject {
  ServerConfig get serverConfig => attributes['serverConfig'];
  set serverConfig(ServerConfig value) => attributes['serverConfig'] = value;

  MailAuthentication get authentication => attributes['authentication'];
  set authentication(MailAuthentication value) => attributes['authentication'] = value;

  List<Capability> get serverCapabilities => attributes['serverCapabilities'];
  set serverCapabilities(List<Capability> value) => attributes['serverCapabilities'] = value;

  String get pathSeparator => attributes['pathSeparator'];
  set pathSeparator(String value) => attributes['pathSeparator'] = value;

  MailServerConfig({ServerConfig serverConfig, MailAuthentication authentication, List<Capability> serverCapabilities, String pathSeparator}) {
    this.serverConfig = serverConfig;
    this.authentication = authentication;
    this.serverCapabilities = serverCapabilities;
    this.pathSeparator = pathSeparator;
    objectCreators['serverConfig'] = (map) => ServerConfig();
    objectCreators['authentication'] = (map) => MailAuthentication.createType(map['typeName']);
    objectCreators['serverCapabilities'] = (map) => <Capability>[];
    objectCreators['serverCapabilities.value'] = (map) => Capability(null); //TODO make capability serializable
  }

  bool supports(String capabilityName) {
    return (serverCapabilities?.firstWhere((c) => c.name == capabilityName, orElse: () => null) != null);
  }

  @override
  bool operator ==(o) => o is MailServerConfig && o.pathSeparator == pathSeparator && o.serverCapabilities?.length == serverCapabilities?.length && o.authentication == authentication && o.serverConfig == serverConfig;

  @override
  String toString() {
    return Serializer().serialize(this);
  }
}
