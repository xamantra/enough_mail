import 'dart:convert';
import '../smtp_command.dart';

class SmtpAuthPlainCommand extends SmtpCommand {
  final String _userName;
  final String _password;

  SmtpAuthPlainCommand(this._userName, this._password) : super('AUTH PLAIN');

  @override
  String getCommand() {
    var combined = _userName + '\u{0000}' + _userName + '\u{0000}' + _password;
    var codec = Base64Codec();
    var encoded = codec.encode(combined.codeUnits);
    return 'AUTH PLAIN ' + encoded;
  }

  @override
  String toString() {
    return 'AUTH PLAIN <password scrambled>';
  }
}
