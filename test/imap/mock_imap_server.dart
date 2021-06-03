import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:enough_mail/imap/mailbox.dart';

enum ServerState { notAuthenticated, authenticated, selected }

class ServerMailbox extends Mailbox {
  List<ServerMailbox> children = <ServerMailbox>[];
  List<int> messageSequenceIdsUnseen;
  List<String> noopChanges;

  ServerMailbox(String name, List<MailboxFlag> flags, String messageFlags,
      String permanentMessageFlags)
      : super.setup(name, name, flags) {
    super.messageFlags = messageFlags.split(' ');
    super.permanentMessageFlags = permanentMessageFlags.split(' ');
  }
}

/// Simple IMAP mock server for testing purposes
class MockImapServer {
  final Socket _socket;
  ServerState state = ServerState.notAuthenticated;
  static const String _CRLF = '\r\n';
  static const String PathSeparatorSlash = '/';
  static const String PathSeperatorDot = '.';
  String pathSeparator = PathSeparatorSlash;
  List<ServerMailbox> mailboxes = <ServerMailbox>[];
  List<ServerMailbox> mailboxesSubscribed = <ServerMailbox>[];
  List<String> fetchResponses = <String>[];
  List<String> getMetaDataResponses = <String>[];
  List<String> setMetaDataResponses = <String>[];
  List<String> storeResponses = <String>[];
  List<String> expungeResponses = <String>[];
  List<String> enableResponses;
  ServerMailbox _selectedMailbox;

  String _idleTag;
  bool _isInAppend = false;
  String _appendTag;
  String overrideResponse;

  static MockImapServer connect(Socket socket) {
    return MockImapServer(socket);
  }

  MockImapServer(this._socket) {
    _socket.listen((data) {
      parseRequest(data);
    }, onDone: () {
      print('server connection done');
    }, onError: (error) {
      print('server error: $error');
    });
  }

  void parseRequest(Uint8List data) {
    var line = String.fromCharCodes(data);
    //print('SERVER RECEIVED: ${line.length}:[$line]. isInAppend=$_isInAppend');
    if (_isInAppend) {
      var response = respondAppend(line);
      writeln(_appendTag + ' ' + response);
      return;
    }
    var firstSpaceIndex = line.indexOf(' ');
    if (firstSpaceIndex == -1) {
      // this could still be valid after a continuation request from this server
      if (line.startsWith('DONE') && _idleTag != null) {
        writeln(_idleTag + ' OK IDLE finished.');
        _idleTag = null;
        return;
      }
      processInvalidRequest('<notag>', line);
    }
    var tag = line.substring(0, firstSpaceIndex);
    var request = line.substring(firstSpaceIndex + 1);
    String Function(String) function;
    if (request.startsWith('CAPABILITY')) {
      function = respondCapability;
    } else if (request.startsWith('LOGIN ')) {
      function = respondLogin;
    } else if (request.startsWith('AUTHENTICATE XOAUTH2 ')) {
      function = respondAuthenticateXOAuth2;
    } else if (request.startsWith('AUTHENTICATE OAUTHBEARER ')) {
      function = respondAuthenticateOAuthBearer;
    } else if (request.startsWith('LIST ')) {
      function = respondList;
    } else if (request.startsWith('LSUB ')) {
      function = respondLsub;
    } else if (request.startsWith('SELECT ')) {
      function = respondSelect;
    } else if (request.startsWith('SEARCH ') ||
        request.startsWith('UID SEARCH ')) {
      function = respondSearch;
    } else if (request.startsWith('NOOP') || request.startsWith('CHECK')) {
      function = respondNoop;
    } else if (request.startsWith('CLOSE')) {
      function = respondClose;
    } else if (request.startsWith('LOGOUT')) {
      function = respondLogout;
    } else if (request.startsWith('FETCH ') ||
        request.startsWith('UID FETCH ')) {
      function = respondFetch;
    } else if (request.startsWith('GETMETADATA')) {
      function = respondGetMetaData;
    } else if (request.startsWith('SETMETADATA')) {
      function = respondSetMetaData;
    } else if (request.startsWith('APPEND')) {
      _appendTag = tag;
      function = respondAppend;
    } else if (request.startsWith('IDLE')) {
      _idleTag = tag;
      function = respondIdle;
    } else if (request.startsWith('COPY ') || request.startsWith('UID COPY ')) {
      function = respondCopy;
    } else if (request.startsWith('MOVE ') || request.startsWith('UID MOVE ')) {
      function = respondMove;
    } else if (request.startsWith('STORE ') ||
        request.startsWith('UID STORE ')) {
      function = respondStore;
    } else if (request.startsWith('EXPUNGE') ||
        request.startsWith('UID EXPUNGE ')) {
      function = respondExpunge;
    } else if (request.startsWith('ENABLE ')) {
      function = respondEnable;
    } else if (request.startsWith('SETQUOTA ')) {
      function = respondSetquota;
    } else if (request.startsWith('GETQUOTA ')) {
      function = respondQuota;
    } else if (request.startsWith('GETQUOTAROOT ')) {
      function = respondQuotaroot;
    }

    if (function != null) {
      var response = function(request);
      if (overrideResponse != null) {
        response = overrideResponse;
      }
      if (response != null) {
        writeln(tag + ' ' + response);
      }
    } else {
      processInvalidRequest(tag, line);
    }
  }

  void writeUntagged(String response) {
    writeln('* ' + response);
  }

  void writeln(String data) {
    //print("SERVER ANSWERS: " + data);
    _socket.writeln(data);
  }

  void write(String data) {
    _socket.write(data);
  }

  void processInvalidRequest(String tag, String line) {
    print('encountered unsupported request: ' + line);
    writeln(tag + ' BAD unsupported request: ' + line);
  }

  String respondCapability(String line) {
    _writeCapabilities();
    return 'OK CAPABILITY completed';
  }

  String respondLogin(String line) {
    if (line == 'LOGIN testuser testpassword' + _CRLF) {
      state = ServerState.authenticated;
      _writeCapabilities();
      return 'OK LOGIN completed';
    }
    return 'NO user unknown or password wrong';
  }

  String respondAuthenticateXOAuth2(String line) {
    var base64Text =
        line.substring('AUTHENTICATE XOAUTH2 '.length, line.length - 2);
    var decoded = utf8.decode(base64.decode(base64Text));
    var splitIndex = decoded.indexOf('\u{0001}', 'user='.length);
    if (splitIndex != -1) {
      var user = decoded.substring('user='.length, splitIndex);
      var token = decoded.substring(
          splitIndex + 1 + 'auth=Bearer '.length, decoded.length - 2);
      if (user == 'testuser' && token == 'ABC123456789abc') {
        state = ServerState.authenticated;
        return 'OK Success';
      }
    }
    return 'NO SASL authentication failed';
  }

  String respondAuthenticateOAuthBearer(String line) {
    var base64Text =
        line.substring('AUTHENTICATE OAUTHBEARER '.length, line.length - 2);
    var decoded = utf8.decode(base64.decode(base64Text));
    //print('decoded=[$decoded]');
    var splitIndex = decoded.indexOf('\u{0001}', 'n,a='.length);
    if (splitIndex != -1) {
      var user = decoded.substring('n,a='.length, splitIndex - 1);
      var hostEndIndex = decoded.indexOf('\u{0001}', splitIndex + 1);
      if (hostEndIndex != -1) {
        var host =
            decoded.substring(splitIndex + 1 + 'host='.length, hostEndIndex);
        var portEndIndex = decoded.indexOf('\u{0001}', hostEndIndex + 1);
        if (portEndIndex != -1) {
          var port = decoded.substring(
              hostEndIndex + 1 + 'port='.length, portEndIndex);
          var token = decoded.substring(
              portEndIndex + 1 + 'auth=Bearer '.length, decoded.length - 2);
          //print('user=[$user], host=[$host], port=[$port] token=[$token]');
          if (user == 'testuser' &&
              token == 'ABC123456789abc' &&
              host != null &&
              port != null) {
            state = ServerState.authenticated;
            return 'OK Success';
          }
        }
      }
    }
    return 'NO SASL authentication failed';
  }

  String respondList(String line) {
    return _respondListLike(line, 'LIST', mailboxes);
  }

  String respondLsub(String line) {
    //print('LSUB request: $line\nsubscribed boxes: ${mailboxesSubscribed.length}');
    return _respondListLike(line, 'LSUB', mailboxesSubscribed);
  }

  String respondSelect(String line) {
    var boxName = line.substring(
        'SELECT '.length, line.indexOf('\r', 'SELECT '.length + 1));
    var box = mailboxes.firstWhere((box) => box.name.startsWith(boxName));
    if (box == null) {
      return 'BAD unknown mailbox in ' + line;
    }
    state = ServerState.selected;
    _selectedMailbox = box;
    var response = '* FLAGS (${_toString(box.messageFlags)})\r\n'
        '* OK [PERMANENTFLAGS (${_toString(box.permanentMessageFlags)})] Flags permitted\r\n'
        '* ${box.messagesExists} EXISTS\r\n'
        '* OK [UNSEEN ${box.firstUnseenMessageSequenceId}] First unseen.\r\n'
        '* OK [UIDVALIDITY ${box.uidValidity}] UIDs valid\r\n'
        '* ${box.messagesRecent} RECENT\r\n'
        '* OK [UIDNEXT ${box.uidNext}] Predicted next UID\r\n'
        '* OK [HIGHESTMODSEQ ${box.highestModSequence}] Highest\r\n';
    write(response);
    return 'OK [READ-WRITE] Select completed (0.088 + 0.000 + 0.087 secs).';
  }

  String respondIdle(String line) {
    write('+ idling\r\n');
    write('* OK Still here\r\n');
    return null; //'OK IDLE MODE started...';
  }

  String respondSearch(String line) {
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    var prefix = line.startsWith('UID') ? ' UID' : '';
    var searchQuery =
        line.substring(prefix.length + 'SEARCH '.length, line.length - 2);
    List<int> sequenceIds;
    if (searchQuery == 'UNSEEN') {
      sequenceIds = box.messageSequenceIdsUnseen;
    }
    if (sequenceIds == null) {
      return 'BAD search not supported: ' +
          line +
          ' query=[' +
          searchQuery +
          ']';
    }
    writeUntagged('SEARCH ' + _toString(sequenceIds));
    return 'OK$prefix SEARCH completed (0.019 + 0.000 + 0.018 secs).';
  }

  String respondNoop(String line) {
    var box = _selectedMailbox;
    if (box != null) {
      if (box.noopChanges != null) {
        for (var change in box.noopChanges) {
          writeUntagged(change);
        }
      }
    }
    return 'OK $line completed (0.001 + 0.077 secs).';
  }

  String respondClose(String line) {
    var box = _selectedMailbox;
    if (box != null) {
      _selectedMailbox = null;
      state = ServerState.authenticated;
      return 'OK CLOSE completed (0.001 + 0.037 secs).';
    }
    return 'NO you need to SELECT a mailbox first';
  }

  String respondLogout(String line) {
    if (state == ServerState.authenticated || state == ServerState.selected) {
      _selectedMailbox = null;
      state = ServerState.notAuthenticated;
      writeUntagged('BYE');
      return 'OK LOGOUT completed (0.000 + 0.017 secs).';
    }
    return 'NO you have to LOGIN first';
  }

  String respondFetch(String line) {
    //print('fetchRequest: $line');
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    var isLastMessageEndingWithLiteral = false;
    for (var fetch in fetchResponses) {
      if (isLastMessageEndingWithLiteral) {
        write(fetch);
      } else {
        writeUntagged(fetch);
        isLastMessageEndingWithLiteral = fetch[fetch.length - 1] == '}';
      }
    }
    var prefix = line.startsWith('UID') ? ' UID' : '';
    return 'OK$prefix FETCH completed (0.001 + 0.000 secs).';
  }

  String respondGetMetaData(String line) {
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    for (var line in getMetaDataResponses) {
      write(line);
    }
    return 'OK GETMEDATA completed (0.001 + 0.000 secs).';
  }

  String respondSetMetaData(String line) {
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    for (var line in setMetaDataResponses) {
      write(line);
    }
    return 'OK SETMEDATA completed (0.001 + 0.000 secs).';
  }

  String respondAppend(String line) {
    if (!_isInAppend) {
      _isInAppend = true;
      write('+ OK\r\n');
      return null;
    } else {
      _isInAppend = false;
      return 'OK [APPENDUID 1466002016 176] Append completed (0.068 + 0.059 + 0.051 secs).';
    }
  }

  String respondCopy(String line) {
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    var prefix = line.startsWith('UID') ? ' UID' : '';
    return 'OK$prefix COPY completed (0.001 + 0.000 secs).';
  }

  String respondMove(String line) {
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    var prefix = line.startsWith('UID') ? ' UID' : '';
    return 'OK$prefix MOVE completed (0.001 + 0.000 secs).';
  }

  String respondStore(String line) {
    //print('store request: $line');
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    if (!line.contains('.SILENT')) {
      // provide the updated list for each specified message:
      for (var line in storeResponses) {
        write(line);
      }
    }
    var prefix = line.startsWith('UID') ? ' UID' : '';
    return 'OK$prefix STORE completed (0.001 + 0.000 secs).';
  }

  String respondExpunge(String line) {
    var box = _selectedMailbox;
    if ((state != ServerState.authenticated && state != ServerState.selected) ||
        (box == null)) {
      return 'NO not authenticated or no mailbox selected';
    }
    // provide the updated list for each specified message:
    for (var line in expungeResponses) {
      write(line);
    }
    var prefix = line.startsWith('UID') ? ' UID' : '';
    return 'OK$prefix EXPUNGE completed (0.002 + 0.000 secs).';
  }

  String respondEnable(String line) {
    if (enableResponses != null) {
      for (var line in enableResponses) {
        write(line);
      }
    }
    return 'OK ENABLED completed (0.002 + 0.000 secs).';
  }

  String respondSetquota(String line) {
    var boxName = line.substring(
        'SETQUOTA '.length, line.indexOf('(', 'SETQUOTA '.length + 1) - 1);
    writeUntagged('QUOTA $boxName (STORAGE 0 120 MESSAGES 0 5000)');
    return 'OK Setquota completed (0.001 + 0.120 secs).';
  }

  String respondQuota(String line) {
    var boxName = line.substring(
        'GETQUOTA '.length, line.indexOf('\r', 'GETQUOTA '.length + 1));
    writeUntagged('QUOTA $boxName (STORAGE 100 1000 TRASH 3 10)');
    return 'OK Getquota completed (0.001 + 0.000 secs).';
  }

  String respondQuotaroot(String line) {
    var boxName = line.substring(
        'GETQUOTAROOT '.length, line.indexOf('\r', 'GETQUOTAROOT '.length + 1));
    writeUntagged('QUOTAROOT $boxName "User quota"');
    writeUntagged('QUOTA "User quota" (STORAGE 232885 1048576)');
    return 'OK Getquotaroot completed (0.002 + 0.000 + 0.001 secs).';
  }

  String _toString(List elements, [String separator = ' ']) {
    return elements.join(separator);
  }

  String _respondListLike(String line, String command, List<Mailbox> boxes) {
    if (state != ServerState.authenticated && state != ServerState.selected) {
      return 'BAD not authenticated';
    } else if (line.startsWith(command + ' "" %')) {
      return _respondListMailboxes(command, boxes);
    } else if (line.startsWith(command) && line.endsWith(' %' + _CRLF)) {
      var boxName = line.substring(command.length + 1, line.lastIndexOf(' %'));
      var isListChildren = false;
      if (boxName.endsWith(pathSeparator)) {
        boxName = boxName.substring(0, boxName.length - 2);
        isListChildren = true;
      }
      var matches = List<Mailbox>.from(boxes);
      matches.retainWhere((box) => box.name.startsWith(boxName));
      if (isListChildren) {
        // TODO allow to list children
      }
      return _respondListMailboxes(command, matches);
    } else {
      return 'NO mockimplementation does not support ' + line;
    }
  }

  String _respondListMailboxes(String command, List<Mailbox> boxes) {
    for (var box in boxes) {
      var boxText = command + ' (';
      var addSpace = false;
      for (var flag in box.flags) {
        if (addSpace) {
          boxText += ' ';
        }
        switch (flag) {
          case MailboxFlag.hasNoChildren:
            addSpace = true;
            boxText += '\\HasNoChildren';
            break;
          case MailboxFlag.hasChildren:
            addSpace = true;
            boxText += '\\HasChildren';
            break;
          case MailboxFlag.marked:
            addSpace = true;
            boxText += '\\marked';
            break;
          case MailboxFlag.unMarked:
            addSpace = true;
            boxText += '\\unmarked';
            break;
          case MailboxFlag.select:
            addSpace = true;
            boxText += '\\select';
            break;
          case MailboxFlag.noSelect:
            addSpace = true;
            boxText += '\\Noselect';
            break;
          case MailboxFlag.drafts:
            addSpace = true;
            boxText += '\\Drafts';
            break;
          case MailboxFlag.inbox:
            addSpace = true;
            boxText += '\\Inbox';
            break;
          case MailboxFlag.junk:
            addSpace = true;
            boxText += '\\Junk';
            break;
          case MailboxFlag.sent:
            addSpace = true;
            boxText += '\\Sent';
            break;
          case MailboxFlag.trash:
            addSpace = true;
            boxText += '\\Trash';
            break;
          case MailboxFlag.archive:
            addSpace = true;
            boxText += '\\Archive';
            break;
          default:
            return 'BAD ' +
                command +
                ': UNEXPECTED MailboxFlag ' +
                flag.toString() +
                ' encountered';
        }
      }
      boxText += ') "' + pathSeparator + '" ' + box.name;
      writeUntagged(boxText);
    }
    return 'OK ' + command + ' completed (0.166 + 0.000 + 0.165 secs).';
  }

  void _writeCapabilities() {
    writeUntagged('CAPABILITY IMAP4rev1 IDLE METADATA');
  }

  void fire(Duration duration, String s) async {
    await Future.delayed(duration);
    write(s);
  }
}
