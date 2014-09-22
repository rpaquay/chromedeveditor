// Copyright (c) 2014, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

library spark.services_impl;

import 'dart:async';

import 'analyzer.dart' as analyzer;
import 'dart_services.dart';
import 'services_common.dart';
import 'compiler.dart';
import '../dart/sdk.dart';

void init(WorkerToHostHandler hostHandler) {
  final ServicesIsolate servicesIsolate = new ServicesIsolate(hostHandler);
}

/**
 * A `Function` that takes in a [ServiceActionEvent] as a request and returns
 * its response event in a [Future].
 */
typedef Future<ServiceActionEvent> RequestHandler(ServiceActionEvent request);

/**
 * Defines a handler for all worker-side service implementations.
 */
class ServicesIsolate {
  int _topCallId = 0;
  final WorkerToHostHandler _hostHandler;

  // Fired when host originates a message
  Stream<ServiceActionEvent> onHostMessage;

  // Fired when host responds to message
  Stream<ServiceActionEvent> onResponseMessage;

  ChromeService chromeService;
  Map<String, ServiceImpl> _serviceImplsById = {};

  DartSdk sdk;

  ServicesIsolate(this._hostHandler) {
    chromeService = new ChromeService(this);

    StreamController<ServiceActionEvent> hostMessageController =
        new StreamController();
    StreamController<ServiceActionEvent> responseMessageController =
        new StreamController.broadcast();

    onResponseMessage = responseMessageController.stream;
    onHostMessage = hostMessageController.stream;

    _registerServiceImpl(new TestServiceImpl(this));

    _hostHandler.listenFromHost((arg) {
      if (arg is int) {
        // int: send response to "ping" test message.
        _hostHandler.sendToHost(arg);
      } else {
        ServiceActionEvent event = new ServiceActionEvent.fromMap(arg);
        if (event.response) {
          responseMessageController.add(event);
        } else {
          hostMessageController.add(event);
        }
      }
    });

    chromeService.getAppContents('packages/spark/sdk/dart-sdk.bz').then(
        (List<int> sdkContents) {
      sdk = DartSdk.createSdkFromContents(sdkContents);

      _registerServiceImpl(new CompilerServiceImpl(this, sdk));
      _registerServiceImpl(new AnalyzerServiceImpl(this, sdk));

      onHostMessage.listen((ServiceActionEvent event) => _handleMessage(event));
    });
  }

  ServiceImpl getServiceImpl(String serviceId) {
    return _serviceImplsById[serviceId];
  }

  Future<ServiceActionEvent> _onResponseByCallId(String callId) {
    Completer<ServiceActionEvent> completer = new Completer<ServiceActionEvent>();
    // Added to avoid leaking subscriptions. Consider using a map of completers.
    StreamSubscription sub = null;
    sub = onResponseMessage.listen((ServiceActionEvent event) {
      if (event.callId == callId) {
        completer.complete(event);
        sub.cancel();
      }
    });
    return completer.future;
  }

  void _registerServiceImpl(ServiceImpl serviceImplementation) {
    _serviceImplsById[serviceImplementation.serviceId] = serviceImplementation;
  }

  Future<ServiceActionEvent> _handleMessage(ServiceActionEvent event) {
    Completer<ServiceActionEvent> completer = new Completer<ServiceActionEvent>();

    ServiceImpl service = getServiceImpl(event.serviceId);
    service.handleEvent(event).then((ServiceActionEvent responseEvent) {
      if (responseEvent != null) {
        _sendResponse(responseEvent);
        completer.complete();
      }
    });

    return completer.future;
  }

  // Sends a response message.
  void _sendResponse(ServiceActionEvent event, [Map data,
      bool expectResponse = false]) {
    // TODO(ericarnold): implement expectResponse
    event.response = true;
    var eventMap = event.toMap();
    if (data != null) {
      eventMap['data'] = data;
    }
    _hostHandler.sendToHost(eventMap);
  }

  String _getNewCallId() => "iso_${_topCallId++}";

  // Sends action to host. Returns a future if expectResponse is true.
  Future<ServiceActionEvent> _sendAction(ServiceActionEvent event,
      [bool expectResponse = false]) {

    event.makeRespondable(_getNewCallId());

    var eventMap = event.toMap();
    _hostHandler.sendToHost(eventMap);
    return _onResponseByCallId(event.callId);
  }
}

class TestServiceImpl extends ServiceImpl {
  TestServiceImpl(ServicesIsolate isolate) : super(isolate, 'test') {
    registerRequestHandler('shortTest', shortTest);
    registerRequestHandler('longTest', longTest);
    registerRequestHandler('readText', readText);
  }

  Future<ServiceActionEvent> shortTest(ServiceActionEvent request) {
    Map map = {"response": "short${request.data['name']}"};
    return new Future.value(request.createReponse(map));
  }

  Future<ServiceActionEvent> longTest(ServiceActionEvent request) {
    return isolate.chromeService.delay(1000).then((_) {
      Map map = {"response": "long${request.data['name']}"};
      return new Future.value(request.createReponse(map));
    });
  }

  Future<ServiceActionEvent> readText(ServiceActionEvent request) {
    String fileUuid = request.data['fileUuid'];
    return isolate.chromeService.getFileContents(fileUuid) .then((String contents) {
      return request.createReponse({"contents": contents});
    });
  }
}

class CompilerServiceImpl extends ServiceImpl {
  final DartSdk sdk;
  Compiler compiler;

  CompilerServiceImpl(ServicesIsolate isolate, this.sdk) :
      super(isolate, 'compiler') {

    compiler = Compiler.createCompilerFrom(sdk,
        new _ServiceContentsProvider(isolate.chromeService));

    registerRequestHandler('compileString', compileString);
    registerRequestHandler('compileFile', compileFile);
  }

  Future<ServiceActionEvent> compileString(ServiceActionEvent request) {
    String string = request.data['string'];
    return compiler.compileString(string).then((CompilerResultHolder result) {
      return new Future.value(request.createReponse(result.toMap()));
    });
  }

  Future<ServiceActionEvent> compileFile(ServiceActionEvent request) {
    String fileUuid = request.data['fileUuid'];
    String project = request.data['project'];
    bool csp = request.data['csp'];

    return compiler.compileFile(fileUuid, csp: csp).then((CompilerResultHolder result) {
      return new Future.value(request.createReponse(result.toMap()));
    });
  }
}

class _ServiceContentsProvider implements ContentsProvider {
  final ChromeService chromeService;

  _ServiceContentsProvider(this.chromeService);

  Future<String> getFileContents(String uuid) {
    if (uuid.startsWith('/')) uuid = uuid.substring(1);
    return chromeService.getFileContents(uuid);
  }

  Future<String> getPackageContents(String relativeUuid, String packageRef) {
    return chromeService.getPackageContents(relativeUuid, packageRef);
  }
}

/**
 * Forwards
 */
class AnalyzerServiceImpl extends ServiceImpl {
  DartServices _dartServices;
  analyzer.ChromeDartSdk dartSdk;

  AnalyzerServiceImpl(ServicesIsolate isolate, DartSdk sdk) :
      super(isolate, 'analyzer') {
    dartSdk = analyzer.createSdk(sdk);
    _dartServices = new analyzer.AnalyzerDartServices(
        dartSdk, new _ServiceContentsProvider(isolate.chromeService));

    registerRequestHandler('getOutlineFor', getOutlineFor);
    registerRequestHandler('buildFiles', buildFiles);
    registerRequestHandler('createContext', createContext);
    registerRequestHandler('processContextChanges', processContextChanges);
    registerRequestHandler('disposeContext', disposeContext);
    registerRequestHandler('getDeclarationFor', getDeclarationFor);
  }

  Future<analyzer.ChromeDartSdk> get dartSdkFuture => new Future.value(dartSdk);

  Future<ServiceActionEvent> buildFiles(ServiceActionEvent request) {
    List<Map> fileUuids = request.data["dartFileUuids"];
    return _buildFiles(fileUuids).then((errorsPerFile) {
      return request.createReponse({"errors": errorsPerFile});
    });
  }

  Future<Map<String, List<Map>>> _buildFiles(List<Map> fileUuids) {
    Map<String, List<Map>> errorsPerFile = {};

    return dartSdkFuture.then((analyzer.ChromeDartSdk sdk) {
      return Future.forEach(fileUuids, (String fileUuid) {
        return _processFile(sdk, fileUuid).then((analyzer.AnalyzerResult result) {
          List<analyzer.AnalysisError> errors = result.errors;
          List<Map> responseErrors = [];

          if (errors != null) {
            for (analyzer.AnalysisError error in errors) {
              AnalysisError responseError = new AnalysisError();
              responseError.message = error.message;
              responseError.offset = error.offset;
              analyzer.LineInfo_Location location = result.getLineInfo(error);
              responseError.lineNumber = location.lineNumber;
              responseError.errorSeverity =
                  _errorSeverityToInt(error.errorCode.errorSeverity);
              responseError.length = error.length;
              responseErrors.add(responseError.toMap());
            }
          }

          return responseErrors;
        }).then((List<Map> errors) {
          errorsPerFile[fileUuid] = errors;
        });
      });
    }).then((_) => errorsPerFile);
  }

  Future<ServiceActionEvent> createContext(ServiceActionEvent request) {
    String id = request.data['contextId'];
    return _dartServices
      .createContext(id)
      .then((_) => request.createReponse());
  }

  Future<ServiceActionEvent> processContextChanges(ServiceActionEvent request) {
    String id = request.data['contextId'];

    List<String> addedUuids = request.data['added'];
    List<String> changedUuids = request.data['changed'];
    List<String> deletedUuids = request.data['deleted'];

    return _dartServices
      .processContextChanges(id, addedUuids, changedUuids, deletedUuids)
      .catchError((error) => request.createErrorReponse(error), test: (e) => e is String)
      .then((AnalysisResultUuid result) => request.createReponse(result.toMap()));
  }

  Future<ServiceActionEvent> disposeContext(ServiceActionEvent request) {
    String id = request.data['contextId'];
    return _dartServices.disposeContext(id);
  }

  Future<ServiceActionEvent> getOutlineFor(ServiceActionEvent request) {
    var codeString = request.data['string'];
    return _dartServices
        .getOutlineFor(codeString)
        .then((Outline result) => request.createReponse(result.toMap()));
  }

  Future<ServiceActionEvent> getDeclarationFor(ServiceActionEvent request) {
    String contextId = request.data['contextId'];
    String fileUuid = request.data['fileUuid'];
    int offset = request.data['offset'];

    return _dartServices
      .getDeclarationFor(contextId, fileUuid, offset)
      .catchError((error) => request.createErrorReponse(error), test: (e) => e is String)
      .then((Declaration declaration) {
        Map map = (declaration == null ? null : declaration.toMap());
        request.createReponse(map);
      });
  }
  int _errorSeverityToInt(analyzer.ErrorSeverity severity) {
    if (severity == analyzer.ErrorSeverity.ERROR) {
      return ErrorSeverity.ERROR;
    } else  if (severity == analyzer.ErrorSeverity.WARNING) {
      return ErrorSeverity.WARNING;
    } else  if (severity == analyzer.ErrorSeverity.INFO) {
      return ErrorSeverity.INFO;
    } else {
      return ErrorSeverity.NONE;
    }
  }

  /**
   * Analyzes file and returns a Future with the [AnalyzerResult].
   */
  Future<analyzer.AnalyzerResult> _processFile(analyzer.ChromeDartSdk sdk, String fileUuid) {
    return isolate.chromeService.getFileContents(fileUuid)
        .then((String contents) => analyzer.analyzeString(sdk, contents))
        .then((analyzer.AnalyzerResult result) => result);
  }
}

/**
 * Special service for calling back to chrome.
 */
class ChromeService {
  ServicesIsolate _isolate;

  ChromeService(this._isolate);

  ServiceActionEvent _createNewEvent(String actionId, [Map data]) {
    return new ServiceActionEvent("chrome", actionId, data);
  }

  Future<ServiceActionEvent> delay(int milliseconds) =>
      _sendAction(_createNewEvent("delay", {"ms": milliseconds}));

  /**
   * Return the contents of the file at the given path. The path is relative to
   * the Chrome app's directory.
   */
  Future<List<int>> getAppContents(String path) {
    return _sendAction(_createNewEvent("getAppContents", {"path": path}))
        .then((ServiceActionEvent event) => event.data['contents']);
  }

  Future<String> getFileContents(String uuid) =>
    _sendAction(_createNewEvent("getFileContents", {"uuid": uuid}))
        .then((ServiceActionEvent event) => event.data["contents"]);

  /**
   * Get the contents for the given package reference. [packageRef] should look
   * something like `package:foo/foo.dart`;
   */
  Future<String> getPackageContents(String relativeUuid, String packageRef) {
    var event = _createNewEvent("getPackageContents",
        {"relativeTo": relativeUuid, "packageRef": packageRef});
    return _sendAction(event).then((event) => event.data["contents"]);
  }

  Future<ServiceActionEvent> _sendAction(ServiceActionEvent event,
      [bool expectResponse = false]) {
    return _isolate._sendAction(event, expectResponse).
        then((ServiceActionEvent event) {
      if (event.error != true) {
        return event;
      } else {
        String error = event.data['error'];
        String stackTrace = event.data['stackTrace'];
        throw "ChromeService error: $error\n$stackTrace";
      }
    });
  }
}

/**
 * Provides an abstract class and helper code for service implementations.
 */
abstract class ServiceImpl {
  final String serviceId;
  final ServicesIsolate isolate;

  Map<String, RequestHandler> _responders = {};

  ServiceImpl(this.isolate, this.serviceId);

  void registerRequestHandler(String methodName, RequestHandler responder) {
    _responders[methodName] = responder;
  }

  Future<ServiceActionEvent> handleEvent(ServiceActionEvent event) {
    RequestHandler responder = _responders[event.actionId];

    if (responder == null) {
      return new Future.value(
          event.createErrorReponse("no such method: ${event.actionId}"));
    } else {
      try {
        Future f = responder(event);
        assert(f != null);
        return f.catchError((e, st) {
          return event.createErrorReponse('${e}\n${st}');
        });
      } catch (e, st) {
        return new Future.value(event.createErrorReponse('${e}\n${st}'));
      }
    }
  }
}
