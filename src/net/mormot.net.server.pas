/// HTTP/HTTPS Server Classes
// - this unit is a part of the freeware Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.net.server;

{
  *****************************************************************************

   HTTP Server Classes
   - Shared Server-Side HTTP Process
   - THttpServerSocket/THttpServer HTTP/1.1 Server
   -


  *****************************************************************************

}

interface

{$I ..\mormot.defines.inc}

uses
  sysutils,
  classes,
  mormot.core.base,
  mormot.core.os,
  mormot.core.threads,
  mormot.core.unicode,
  mormot.core.text,
  mormot.net.sock,
  mormot.net.http,
  mormot.net.client;


{ ******************** Shared Server-Side HTTP Process }

type
  /// exception raised during HTTP process
  EHttpServer = class(ESynException);

  {$M+} // to have existing RTTI for published properties
  THttpServerGeneric = class;

  THttpServerRequest = class;
  {$M-}

  /// a genuine identifier for a given client connection on server side
  // - maps http.sys ID, or is a genuine 31-bit value from increasing sequence

  THttpServerConnectionID = Int64;

  /// a dynamic array of client connection identifiers, e.g. for broadcasting
  THttpServerConnectionIDDynArray = array of THttpServerConnectionID;

  /// event handler used by THttpServerGeneric.OnRequest property
  // - Ctxt defines both input and output parameters
  // - result of the function is the HTTP error code (200 if OK, e.g.)
  // - OutCustomHeader will handle Content-Type/Location
  // - if OutContentType is STATICFILE_CONTENT_TYPE (i.e. '!STATICFILE'),
  // then OutContent is the UTF-8 filename of a file to be sent directly
  // to the client via http.sys or NGINX's X-Accel-Redirect; the
  // OutCustomHeader should contain the eventual 'Content-type: ....' value
  TOnHttpServerRequest = function(Ctxt: THttpServerRequest): cardinal of object;

  /// event handler used by THttpServerGeneric.OnAfterResponse property
  // - Ctxt defines both input and output parameters
  // - Code defines the HTTP response code the (200 if OK, e.g.)
  TOnHttpServerAfterResponse = procedure(Ctxt: THttpServerRequest;
    const Code: cardinal) of object;

  /// event handler used by THttpServerGeneric.OnBeforeBody property
  // - if defined, is called just before the body is retrieved from the client
  // - supplied parameters reflect the current input state
  // - should return STATUS_SUCCESS=200 to continue the process, or an HTTP
  // error code (e.g. STATUS_FORBIDDEN or STATUS_PAYLOADTOOLARGE) to reject
  // the request
  TOnHttpServerBeforeBody = function(const aURL, aMethod, aInHeaders,
    aInContentType, aRemoteIP: RawUTF8; aContentLength: integer;
    aUseSSL: boolean): cardinal of object;

  /// the server-side available authentication schemes
  // - as used by THttpServerRequest.AuthenticationStatus
  // - hraNone..hraKerberos will match low-level HTTP_REQUEST_AUTH_TYPE enum as
  // defined in HTTP 2.0 API and
  THttpServerRequestAuthentication = (
    hraNone, hraFailed, hraBasic, hraDigest, hraNtlm, hraNegotiate, hraKerberos);

  /// a generic input/output structure used for HTTP server requests
  // - URL/Method/InHeaders/InContent properties are input parameters
  // - OutContent/OutContentType/OutCustomHeader are output parameters
  THttpServerRequest = class
  protected
    fRemoteIP, fURL, fMethod, fInHeaders, fInContentType, fAuthenticatedUser,
      fOutContentType, fOutCustomHeaders: RawUTF8;
    fInContent, fOutContent: RawByteString;
    fServer: THttpServerGeneric;
    fRequestID: integer;
    fConnectionID: THttpServerConnectionID;
    fConnectionThread: TSynThread;
    fUseSSL: boolean;
    fAuthenticationStatus: THttpServerRequestAuthentication;
    {$ifdef MSWINDOWS}
    fHttpApiRequest: Pointer;
    fFullURL: SynUnicode;
    {$endif MSWINDOWS}
  public
    /// low-level property which may be used during requests processing
    Status: integer;
    /// initialize the context, associated to a HTTP server instance
    constructor Create(aServer: THttpServerGeneric;
      aConnectionID: THttpServerConnectionID; aConnectionThread: TSynThread); virtual;
    /// prepare an incoming request
    // - will set input parameters URL/Method/InHeaders/InContent/InContentType
    // - will reset output parameters
    procedure Prepare(const aURL, aMethod, aInHeaders: RawUTF8;
      const aInContent: RawByteString; const aInContentType, aRemoteIP: RawUTF8;
      aUseSSL: boolean = false);
    /// append some lines to the InHeaders input parameter
    procedure AddInHeader(additionalHeader: RawUTF8);
    {$ifdef MSWINDOWS}
    /// input parameter containing the caller Full URL
    property FullURL: SynUnicode read fFullURL;
    {$endif MSWINDOWS}
    /// input parameter containing the caller URI
    property URL: RawUTF8 read fURL;
    /// input parameter containing the caller method (GET/POST...)
    property Method: RawUTF8 read fMethod;
    /// input parameter containing the caller message headers
    property InHeaders: RawUTF8 read fInHeaders;
    /// input parameter containing the caller message body
    // - e.g. some GET/POST/PUT JSON data can be specified here
    property InContent: RawByteString read fInContent;
    // input parameter defining the caller message body content type
    property InContentType: RawUTF8 read fInContentType;
    /// output parameter to be set to the response message body
    property OutContent: RawByteString read fOutContent write fOutContent;
    /// output parameter to define the reponse message body content type
    // - if OutContentType is STATICFILE_CONTENT_TYPE (i.e. '!STATICFILE'),
    // then OutContent is the UTF-8 file name of a file to be sent to the
    // client via http.sys or NGINX's X-Accel-Redirect header (faster than
    // local buffering/sending)
    // - if OutContentType is NORESPONSE_CONTENT_TYPE (i.e. '!NORESPONSE'), then
    // the actual transmission protocol may not wait for any answer - used
    // e.g. for WebSockets
    property OutContentType: RawUTF8 read fOutContentType write fOutContentType;
    /// output parameter to be sent back as the response message header
    // - e.g. to set Content-Type/Location
    property OutCustomHeaders: RawUTF8 read fOutCustomHeaders write fOutCustomHeaders;
    /// the associated server instance
    // - may be a THttpServer or a THttpApiServer class
    property Server: THttpServerGeneric read fServer;
    /// the client remote IP, as specified to Prepare()
    property RemoteIP: RawUTF8 read fRemoteIP write fRemoteIP;
    /// a 31-bit sequential number identifying this instance on the server
    property RequestID: integer read fRequestID;
    /// the ID of the connection which called this execution context
    // - e.g. SynCrtSock's TWebSocketProcess.NotifyCallback method would use
    // this property to specify the client connection to be notified
    // - is set as an Int64 to match http.sys ID type, but will be an
    // increasing 31-bit integer sequence for (web)socket-based servers
    property ConnectionID: THttpServerConnectionID read fConnectionID;
    /// the thread which owns the connection of this execution context
    // - depending on the HTTP server used, may not follow ConnectionID
    property ConnectionThread: TSynThread read fConnectionThread;
    /// is TRUE if the caller is connected via HTTPS
    // - only set for THttpApiServer class yet
    property UseSSL: boolean read fUseSSL;
    /// contains the THttpServer-side authentication status
    // - e.g. when using http.sys authentication with HTTP API 2.0
    property AuthenticationStatus: THttpServerRequestAuthentication
      read fAuthenticationStatus;
    /// contains the THttpServer-side authenticated user name, UTF-8 encoded
    // - e.g. when using http.sys authentication with HTTP API 2.0, the
    // domain user name is retrieved from the supplied AccessToken
    // - could also be set by the THttpServerGeneric.Request() method, after
    // proper authentication, so that it would be logged as expected
    property AuthenticatedUser: RawUTF8 read fAuthenticatedUser;
    {$ifdef MSWINDOWS}
    /// for THttpApiServer, points to a PHTTP_REQUEST structure
    // - not used by now for other servers
    property HttpApiRequest: Pointer read fHttpApiRequest;
    {$endif MSWINDOWS}
  end;

  /// abstract class to implement a server thread
  // - do not use this class, but rather the THttpServer, THttpApiServer
  // or TAsynchFrameServer (as defined in SynBidirSock)
  TServerGeneric = class(TSynThread)
  protected
    fProcessName: RawUTF8;
    fOnHttpThreadStart: TNotifyThreadEvent;
    procedure SetOnTerminate(const Event: TNotifyThreadEvent); virtual;
    procedure NotifyThreadStart(Sender: TSynThread);
  public
    /// initialize the server instance, in non suspended state
    constructor Create(CreateSuspended: boolean;
      const OnStart, OnStop: TNotifyThreadEvent;
      const ProcessName: RawUTF8); reintroduce; virtual;
  end;

  /// abstract class to implement a HTTP server
  // - do not use this class, but rather the THttpServer or THttpApiServer
  THttpServerGeneric = class(TServerGeneric)
  protected
    fShutdownInProgress: boolean;
    /// optional event handlers for process interception
    fOnRequest: TOnHttpServerRequest;
    fOnBeforeBody: TOnHttpServerBeforeBody;
    fOnBeforeRequest: TOnHttpServerRequest;
    fOnAfterRequest: TOnHttpServerRequest;
    fOnAfterResponse: TOnHttpServerAfterResponse;
    fMaximumAllowedContentLength: cardinal;
    /// list of all registered compression algorithms
    fCompress: THttpSocketCompressRecDynArray;
    /// set by RegisterCompress method
    fCompressAcceptEncoding: RawUTF8;
    fServerName: RawUTF8;
    fCurrentConnectionID: integer; // 31-bit NextConnectionID sequence
    fCurrentRequestID: integer;
    fCanNotifyCallback: boolean;
    fRemoteIPHeader, fRemoteIPHeaderUpper: RawUTF8;
    fRemoteConnIDHeader, fRemoteConnIDHeaderUpper: RawUTF8;
    function GetAPIVersion: string; virtual; abstract;
    procedure SetServerName(const aName: RawUTF8); virtual;
    procedure SetOnRequest(const aRequest: TOnHttpServerRequest); virtual;
    procedure SetOnBeforeBody(const aEvent: TOnHttpServerBeforeBody); virtual;
    procedure SetOnBeforeRequest(const aEvent: TOnHttpServerRequest); virtual;
    procedure SetOnAfterRequest(const aEvent: TOnHttpServerRequest); virtual;
    procedure SetOnAfterResponse(const aEvent: TOnHttpServerAfterResponse); virtual;
    procedure SetMaximumAllowedContentLength(aMax: cardinal); virtual;
    procedure SetRemoteIPHeader(const aHeader: RawUTF8); virtual;
    procedure SetRemoteConnIDHeader(const aHeader: RawUTF8); virtual;
    function GetHTTPQueueLength: Cardinal; virtual; abstract;
    procedure SetHTTPQueueLength(aValue: Cardinal); virtual; abstract;
    function DoBeforeRequest(Ctxt: THttpServerRequest): cardinal;
    function DoAfterRequest(Ctxt: THttpServerRequest): cardinal;
    procedure DoAfterResponse(Ctxt: THttpServerRequest; const Code: cardinal); virtual;
    function NextConnectionID: integer; // 31-bit internal sequence
  public
    /// initialize the server instance, in non suspended state
    constructor Create(CreateSuspended: boolean; 
      const OnStart, OnStop: TNotifyThreadEvent;
      const ProcessName: RawUTF8); reintroduce; virtual;
    /// override this function to customize your http server
    // - InURL/InMethod/InContent properties are input parameters
    // - OutContent/OutContentType/OutCustomHeader are output parameters
    // - result of the function is the HTTP error code (200 if OK, e.g.),
    // - OutCustomHeader is available to handle Content-Type/Location
    // - if OutContentType is STATICFILE_CONTENT_TYPE (i.e. '!STATICFILE'),
    // then OutContent is the UTF-8 filename of a file to be sent directly
    // to the client via http.sys or NGINX's X-Accel-Redirect; the
    // OutCustomHeader should contain the eventual 'Content-type: ....' value
    // - default implementation is to call the OnRequest event (if existing),
    // and will return STATUS_NOTFOUND if OnRequest was not set
    // - warning: this process must be thread-safe (can be called by several
    // threads simultaneously, but with a given Ctxt instance for each)
    function Request(Ctxt: THttpServerRequest): cardinal; virtual;
    /// server can send a request back to the client, when the connection has
    // been upgraded e.g. to WebSockets
    // - InURL/InMethod/InContent properties are input parameters (InContentType
    // is ignored)
    // - OutContent/OutContentType/OutCustomHeader are output parameters
    // - CallingThread should be set to the client's Ctxt.CallingThread
    // value, so that the method could know which connnection is to be used -
    // it will return STATUS_NOTFOUND (404) if the connection is unknown
    // - result of the function is the HTTP error code (200 if OK, e.g.)
    // - warning: this void implementation will raise an ECrtSocket exception -
    // inherited classes should override it, e.g. as in TWebSocketServerRest
    function Callback(Ctxt: THttpServerRequest; aNonBlocking: boolean): cardinal; virtual;
    /// will register a compression algorithm
    // - used e.g. to compress on the fly the data, with standard gzip/deflate
    // or custom (synlzo/synlz) protocols
    // - you can specify a minimal size (in bytes) before which the content won't
    // be compressed (1024 by default, corresponding to a MTU of 1500 bytes)
    // - the first registered algorithm will be the prefered one for compression
    procedure RegisterCompress(aFunction: THttpSocketCompress;
      aCompressMinSize: integer = 1024); virtual;
    /// you can call this method to prepare the HTTP server for shutting down
    procedure Shutdown;
    /// event handler called by the default implementation of the
    // virtual Request method
    // - warning: this process must be thread-safe (can be called by several
    // threads simultaneously)
    property OnRequest: TOnHttpServerRequest
      read fOnRequest write SetOnRequest;
    /// event handler called just before the body is retrieved from the client
    // - should return STATUS_SUCCESS=200 to continue the process, or an HTTP
    // error code to reject the request immediatly, and close the connection
    property OnBeforeBody: TOnHttpServerBeforeBody
      read fOnBeforeBody write SetOnBeforeBody;
    /// event handler called after HTTP body has been retrieved, before OnProcess
    // - may be used e.g. to return a STATUS_ACCEPTED (202) status to client and
    // continue a long-term job inside the OnProcess handler in the same thread;
    // or to modify incoming information before passing it to main businnes logic,
    // (header preprocessor, body encoding etc...)
    // - if the handler returns > 0 server will send a response immediately,
    // unless return code is STATUS_ACCEPTED (202), then OnRequest will be called
    // - warning: this handler must be thread-safe (can be called by several
    // threads simultaneously)
    property OnBeforeRequest: TOnHttpServerRequest
      read fOnBeforeRequest write SetOnBeforeRequest;
    /// event handler called after request is processed but before response
    // is sent back to client
    // - main purpose is to apply post-processor, not part of request logic
    // - if handler returns value > 0 it will override the OnProcess response code
    // - warning: this handler must be thread-safe (can be called by several
    // threads simultaneously)
    property OnAfterRequest: TOnHttpServerRequest
      read fOnAfterRequest write SetOnAfterRequest;
    /// event handler called after response is sent back to client
    // - main purpose is to apply post-response analysis, logging, etc.
    // - warning: this handler must be thread-safe (can be called by several
    // threads simultaneously)
    property OnAfterResponse: TOnHttpServerAfterResponse
      read fOnAfterResponse write SetOnAfterResponse;
    /// event handler called after each working Thread is just initiated
    // - called in the thread context at first place in THttpServerGeneric.Execute
    property OnHttpThreadStart: TNotifyThreadEvent
      read fOnHttpThreadStart write fOnHttpThreadStart;
    /// event handler called when a working Thread is terminating
    // - called in the corresponding thread context
    // - the TThread.OnTerminate event will be called within a Synchronize()
    // wrapper, so it won't fit our purpose
    // - to be used e.g. to call CoUnInitialize from thread in which CoInitialize
    // was made, for instance via a method defined as such:
    // ! procedure TMyServer.OnHttpThreadTerminate(Sender: TObject);
    // ! begin // TSQLDBConnectionPropertiesThreadSafe
    // !   fMyConnectionProps.EndCurrentThread;
    // ! end;
    // - is used e.g. by TSQLRest.EndCurrentThread for proper multi-threading
    property OnHttpThreadTerminate: TNotifyThreadEvent
      read fOnThreadTerminate write SetOnTerminate;
    /// reject any incoming request with a body size bigger than this value
    // - default to 0, meaning any input size is allowed
    // - returns STATUS_PAYLOADTOOLARGE = 413 error if "Content-Length" incoming
    // header overflow the supplied number of bytes
    property MaximumAllowedContentLength: cardinal
      read fMaximumAllowedContentLength write SetMaximumAllowedContentLength;
    /// defines request/response internal queue length
    // - default value if 1000, which sounds fine for most use cases
    // - for THttpApiServer, will return 0 if the system does not support HTTP
    // API 2.0 (i.e. under Windows XP or Server 2003)
    // - for THttpServer, will shutdown any incoming accepted socket if the
    // internal TSynThreadPool.PendingContextCount+ThreadCount exceeds this limit;
    // each pending connection is a THttpServerSocket instance in the queue
    // - increase this value if you don't have any load-balancing in place, and
    // in case of e.g. many 503 HTTP answers or if many "QueueFull" messages
    // appear in HTTP.sys log files (normally in
    // C:\Windows\System32\LogFiles\HTTPERR\httperr*.log) - may appear with
    // thousands of concurrent clients accessing at once the same server -
    // see @http://msdn.microsoft.com/en-us/library/windows/desktop/aa364501
    // - you can use this property with a reverse-proxy as load balancer, e.g.
    // with nginx configured as such:
    // $ location / {
    // $       proxy_pass              http://balancing_upstream;
    // $       proxy_next_upstream     error timeout invalid_header http_500 http_503;
    // $       proxy_connect_timeout   2;
    // $       proxy_set_header        Host            $host;
    // $       proxy_set_header        X-Real-IP       $remote_addr;
    // $       proxy_set_header        X-Forwarded-For $proxy_add_x_forwarded_for;
    // $       proxy_set_header        X-Conn-ID       $connection
    // $ }
    // see https://synopse.info/forum/viewtopic.php?pid=28174#p28174
    property HTTPQueueLength: cardinal read GetHTTPQueueLength write SetHTTPQueueLength;
    /// TRUE if the inherited class is able to handle callbacks
    // - only TWebSocketServer has this ability by now
    property CanNotifyCallback: boolean read fCanNotifyCallback;
    /// the value of a custom HTTP header containing the real client IP
    // - by default, the RemoteIP information will be retrieved from the socket
    // layer - but if the server runs behind some proxy service, you should
    // define here the HTTP header name which indicates the true remote client
    // IP value, mostly as 'X-Real-IP' or 'X-Forwarded-For'
    property RemoteIPHeader: RawUTF8 read fRemoteIPHeader write SetRemoteIPHeader;
    /// the value of a custom HTTP header containing the real client connection ID
    // - by default, Ctxt.ConnectionID information will be retrieved from our
    // socket layer - but if the server runs behind some proxy service, you should
    // define here the HTTP header name which indicates the real remote connection,
    // for example as 'X-Conn-ID', setting in nginx config:
    //  $ proxy_set_header      X-Conn-ID       $connection
    property RemoteConnIDHeader: RawUTF8
      read fRemoteConnIDHeader write SetRemoteConnIDHeader;
  published
    /// returns the API version used by the inherited implementation
    property APIVersion: string read GetAPIVersion;
    /// the Server name, UTF-8 encoded, e.g. 'mORMot/1.18 (Linux)'
    // - will be served as "Server: ..." HTTP header
    // - for THttpApiServer, when called from the main instance, will propagate
    // the change to all cloned instances, and included in any HTTP API 2.0 log
    property ServerName: RawUTF8 read fServerName write SetServerName;
    /// the associated process name
    property ProcessName: RawUTF8 read fProcessName write fProcessName;
  end;


{ ******************** THttpServerSocket/THttpServer HTTP/1.1 Server }

type
  /// results of THttpServerSocket.GetRequest virtual method
  // - return grError if the socket was not connected any more, or grException
  // if any exception occured during the process
  // - grOversizedPayload is returned when MaximumAllowedContentLength is reached
  // - grRejected is returned when OnBeforeBody returned not 200
  // - grTimeout is returned when HeaderRetrieveAbortDelay is reached
  // - grHeaderReceived is returned for GetRequest({withbody=}false)
  // - grBodyReceived is returned for GetRequest({withbody=}true)
  // - grOwned indicates that this connection is now handled by another thread,
  // e.g. asynchronous WebSockets
  THttpServerSocketGetRequestResult = (
    grError, grException, grOversizedPayload, grRejected,
    grTimeout, grHeaderReceived, grBodyReceived, grOwned);

  {$M+} // to have existing RTTI for published properties
  THttpServer = class;
  {$M-}

  /// Socket API based HTTP/1.1 server class used by THttpServer Threads

  THttpServerSocket = class(THttpSocket)
  protected
    fMethod: RawUTF8;
    fURL: RawUTF8;
    fKeepAliveClient: boolean;
    fRemoteConnectionID: THttpServerConnectionID;
    fServer: THttpServer;
  public
    /// create the socket according to a server
    // - will register the THttpSocketCompress functions from the server
    // - once created, caller should call AcceptRequest() to accept the socket
    constructor Create(aServer: THttpServer); reintroduce;
    /// main object function called after aClientSock := Accept + Create:
    // - get Command, Method, URL, Headers and Body (if withBody is TRUE)
    // - get sent data in Content (if withBody=true and ContentLength<>0)
    // - returned enumeration will indicates the processing state
    function GetRequest(withBody: boolean;
      headerMaxTix: Int64): THttpServerSocketGetRequestResult; virtual;
    /// contains the method ('GET','POST'.. e.g.) after GetRequest()
    property Method: RawUTF8 read fMethod;
    /// contains the URL ('/' e.g.) after GetRequest()
    property URL: RawUTF8 read fURL;
    /// true if the client is HTTP/1.1 and 'Connection: Close' is not set
    // - default HTTP/1.1 behavior is "keep alive", unless 'Connection: Close'
    // is specified, cf. RFC 2068 page 108: "HTTP/1.1 applications that do not
    // support persistent connections MUST include the "close" connection option
    // in every message"
    property KeepAliveClient: boolean read fKeepAliveClient write fKeepAliveClient;
    /// the recognized connection ID, after a call to GetRequest()
    // - identifies either the raw connection on the current server, or is
    // a custom header value set by a local proxy, e.g.
    // THttpServerGeneric.RemoteConnIDHeader='X-Conn-ID' for nginx
    property RemoteConnectionID: THttpServerConnectionID read fRemoteConnectionID;
  end;

  /// HTTP response Thread as used by THttpServer Socket API based class
  // - Execute procedure get the request and calculate the answer, using
  // the thread for a single client connection, until it is closed
  // - you don't have to overload the protected THttpServerResp Execute method:
  // override THttpServer.Request() function or, if you need a lower-level access
  // (change the protocol, e.g.) THttpServer.Process() method itself
  THttpServerResp = class(TSynThread)
  protected
    fServer: THttpServer;
    fServerSock: THttpServerSocket;
    fClientSock: TNetSocket;
    fClientSin: TNetAddr;
    fConnectionID: THttpServerConnectionID;
    /// main thread loop: read request from socket, send back answer
    procedure Execute; override;
  public
    /// initialize the response thread for the corresponding incoming socket
    // - this version will get the request directly from an incoming socket
    constructor Create(aSock: TNetSocket; const aSin: TNetAddr;
      aServer: THttpServer); reintroduce; overload;
    /// initialize the response thread for the corresponding incoming socket
    // - this version will handle KeepAlive, for such an incoming request
    constructor Create(aServerSock: THttpServerSocket; aServer: THttpServer);
      reintroduce; overload; virtual;
    /// the associated socket to communicate with the client
    property ServerSock: THttpServerSocket read fServerSock;
    /// the associated main HTTP server instance
    property Server: THttpServer read fServer;
    /// the unique identifier of this connection
    property ConnectionID: THttpServerConnectionID read fConnectionID;
  end;

  /// metaclass of HTTP response Thread
  THttpServerRespClass = class of THttpServerResp;

  /// a simple Thread Pool, used for fast handling HTTP requests of a THttpServer
  // - will handle multi-connection with less overhead than creating a thread
  // for each incoming request
  // - will create a THttpServerResp response thread, if the incoming request is
  // identified as HTTP/1.1 keep alive, or HTTP body length is bigger than 1 MB
  TSynThreadPoolTHttpServer = class(TSynThreadPool)
  protected
    fServer: THttpServer;
    {$ifndef USE_WINIOCP}
    function QueueLength: integer; override;
    {$endif USE_WINIOCP}
    // here aContext is a THttpServerSocket instance
    procedure Task(aCaller: TSynThread; aContext: Pointer); override;
    procedure TaskAbort(aContext: Pointer); override;
  public
    /// initialize a thread pool with the supplied number of threads
    // - Task() overridden method processs the HTTP request set by Push()
    // - up to 256 threads can be associated to a Thread Pool
    constructor Create(Server: THttpServer; NumberOfThreads: Integer = 32); reintroduce;
  end;

  /// meta-class of the THttpServerSocket process
  // - used to override THttpServerSocket.GetRequest for instance
  THttpServerSocketClass = class of THttpServerSocket;

  /// event handler used by THttpServer.Process to send a local file
  // when STATICFILE_CONTENT_TYPE content-type is returned by the service
  // - can be defined e.g. to use NGINX X-Accel-Redirect header
  // - should return true if the Context has been modified to serve the file, or
  // false so that the file will be manually read and sent from memory
  // - any exception during process will be returned as a STATUS_NOTFOUND page
  TOnHttpServerSendFile = function(Context: THttpServerRequest;
    const LocalFileName: TFileName): boolean of object;

  /// main HTTP server Thread using the standard Sockets API (e.g. WinSock)
  // - bind to a port and listen to incoming requests
  // - assign this requests to THttpServerResp threads from a ThreadPool
  // - it implements a HTTP/1.1 compatible server, according to RFC 2068 specifications
  // - if the client is also HTTP/1.1 compatible, KeepAlive connection is handled:
  //  multiple requests will use the existing connection and thread;
  //  this is faster and uses less resources, especialy under Windows
  // - a Thread Pool is used internaly to speed up HTTP/1.0 connections - a
  // typical use, under Linux, is to run this class behind a NGINX frontend,
  // configured as https reverse proxy, leaving default "proxy_http_version 1.0"
  // and "proxy_request_buffering on" options for best performance, and
  // setting KeepAliveTimeOut=0 in the THttpServer.Create constructor
  // - under windows, will trigger the firewall UAC popup at first run
  // - don't forget to use Free method when you are finished
  THttpServer = class(THttpServerGeneric)
  protected
    /// used to protect Process() call
    fProcessCS: TRTLCriticalSection;
    fHeaderRetrieveAbortDelay: integer;
    fThreadPool: TSynThreadPoolTHttpServer;
    fInternalHttpServerRespList: {$ifdef FPC}TFPList{$else}TList{$endif};
    fServerConnectionCount: integer;
    fServerConnectionActive: integer;
    fServerKeepAliveTimeOut: cardinal;
    fSockPort, fTCPPrefix: RawUTF8;
    fSock: TCrtSocket;
    fThreadRespClass: THttpServerRespClass;
    fOnSendFile: TOnHttpServerSendFile;
    fNginxSendFileFrom: array of TFileName;
    fHTTPQueueLength: cardinal;
    fExecuteState: (esNotStarted, esBinding, esRunning, esFinished);
    fStats: array[THttpServerSocketGetRequestResult] of integer;
    fSocketClass: THttpServerSocketClass;
    fHeadersNotFiltered: boolean;
    fExecuteMessage: string;
    function GetStat(one: THttpServerSocketGetRequestResult): integer;
    function GetHTTPQueueLength: Cardinal; override;
    procedure SetHTTPQueueLength(aValue: Cardinal); override;
    procedure InternalHttpServerRespListAdd(resp: THttpServerResp);
    procedure InternalHttpServerRespListRemove(resp: THttpServerResp);
    function OnNginxAllowSend(Context: THttpServerRequest;
      const LocalFileName: TFileName): boolean;
    // this overridden version will return e.g. 'Winsock 2.514'
    function GetAPIVersion: RawUTF8; override;
    /// server main loop - don't change directly
    procedure Execute; override;
    /// this method is called on every new client connection, i.e. every time
    // a THttpServerResp thread is created with a new incoming socket
    procedure OnConnect; virtual;
    /// this method is called on every client disconnection to update stats
    procedure OnDisconnect; virtual;
    /// override this function in order to low-level process the request;
    // default process is to get headers, and call public function Request
    procedure Process(ClientSock: THttpServerSocket;
      ConnectionID: THttpServerConnectionID; ConnectionThread: TSynThread); virtual;
  public
    /// create a Server Thread, ready to be bound and listening on a port
    // - this constructor will raise a EHttpServer exception if binding failed
    // - expects the port to be specified as string, e.g. '1234'; you can
    // optionally specify a server address to bind to, e.g. '1.2.3.4:1234'
    // - can listed on UDS in case port is specified with 'unix:' prefix, e.g.
    // 'unix:/run/myapp.sock'
    // - on Linux in case aPort is empty string will check if external fd
    // is passed by systemd and use it (so called systemd socked activation)
    // - you can specify a number of threads to be initialized to handle
    // incoming connections. Default is 32, which may be sufficient for most
    // cases, maximum is 256. If you set 0, the thread pool will be disabled
    // and one thread will be created for any incoming connection
    // - you can also tune (or disable with 0) HTTP/1.1 keep alive delay and
    // how incoming request Headers[] are pushed to the processing method
    // - this constructor won't actually do the port binding, which occurs in
    // the background thread: caller should therefore call WaitStarted after
    // THttpServer.Create()
    constructor Create(const aPort: RawUTF8;
      const OnStart, OnStop: TNotifyThreadEvent;
      const ProcessName: RawUTF8; ServerThreadPoolCount: integer = 32;
      KeepAliveTimeOut: integer = 30000; HeadersUnFiltered: boolean = false;
      CreateSuspended: boolean = false); reintroduce; virtual;
    /// ensure the HTTP server thread is actually bound to the specified port
    // - TCrtSocket.Bind() occurs in the background in the Execute method: you
    // should call and check this method result just after THttpServer.Create
    // - initial THttpServer design was to call Bind() within Create, which
    // works fine on Delphi + Windows, but fails with a EThreadError on FPC/Linux
    // - raise a ECrtSocket if binding failed within the specified period (if
    // port is free, it would be almost immediate)
    // - calling this method is optional, but if the background thread didn't
    // actually bind the port, the server will be stopped and unresponsive with
    // no explicit error message, until it is terminated
    procedure WaitStarted(Seconds: integer = 30); virtual;
    /// enable NGINX X-Accel internal redirection for STATICFILE_CONTENT_TYPE
    // - will define internally a matching OnSendFile event handler
    // - generating "X-Accel-Redirect: " header, trimming any supplied left
    // case-sensitive file name prefix, e.g. with NginxSendFileFrom('/var/www'):
    // $ # Will serve /var/www/protected_files/myfile.tar.gz
    // $ # When passed URI /protected_files/myfile.tar.gz
    // $ location /protected_files {
    // $  internal;
    // $  root /var/www;
    // $ }
    // - call this method several times to register several folders
    procedure NginxSendFileFrom(const FileNameLeftTrim: TFileName);
    /// release all memory and handlers
    destructor Destroy; override;
    /// by default, only relevant headers are added to internal headers list
    // - for instance, Content-Length, Content-Type and Content-Encoding are
    // stored as fields in this THttpSocket, but not included in its Headers[]
    // - set this property to true to include all incoming headers
    property HeadersNotFiltered: boolean read fHeadersNotFiltered;
    /// access to the main server low-level Socket
    // - it's a raw TCrtSocket, which only need a socket to be bound, listening
    // and accept incoming request
    // - THttpServerSocket are created on the fly for every request, then
    // a THttpServerResp thread is created for handling this THttpServerSocket
    property Sock: TCrtSocket read fSock;
    /// custom event handler used to send a local file for STATICFILE_CONTENT_TYPE
    // - see also NginxSendFileFrom() method
    property OnSendFile: TOnHttpServerSendFile read fOnSendFile write fOnSendFile;
  published
    /// will contain the current number of connections to the server
    property ServerConnectionActive: integer
      read fServerConnectionActive write fServerConnectionActive;
    /// will contain the total number of connections to the server
    // - it's the global count since the server started
    property ServerConnectionCount: integer
      read fServerConnectionCount write fServerConnectionCount;
    /// time, in milliseconds, for the HTTP/1.1 connections to be kept alive
    // - default is 30000 ms, i.e. 30 seconds
    // - setting 0 here (or in KeepAliveTimeOut constructor parameter) will
    // disable keep-alive, and fallback to HTTP.1/0 for all incoming requests
    // (may be a good idea e.g. behind a NGINX reverse proxy)
    // - see THttpApiServer.SetTimeOutLimits(aIdleConnection) parameter
    property ServerKeepAliveTimeOut: cardinal
      read fServerKeepAliveTimeOut write fServerKeepAliveTimeOut;
    /// the bound TCP port, as specified to Create() constructor
    // - TCrtSocket.Bind() occurs in the Execute method
    property SockPort: RawUTF8 read fSockPort;
    /// TCP/IP prefix to mask HTTP protocol
    // - if not set, will create full HTTP/1.0 or HTTP/1.1 compliant content
    // - in order to make the TCP/IP stream not HTTP compliant, you can specify
    // a prefix which will be put before the first header line: in this case,
    // the TCP/IP stream won't be recognized as HTTP, and will be ignored by
    // most AntiVirus programs, and increase security - but you won't be able
    // to use an Internet Browser nor AJAX application for remote access any more
    property TCPPrefix: RawUTF8 read fTCPPrefix write fTCPPrefix;
    /// the associated thread pool
    // - may be nil if ServerThreadPoolCount was 0 on constructor
    property ThreadPool: TSynThreadPoolTHttpServer read fThreadPool;
    /// milliseconds delay to reject a connection due to too long header retrieval
    // - default is 0, i.e. not checked (typically not needed behind a reverse proxy)
    property HeaderRetrieveAbortDelay: integer
      read fHeaderRetrieveAbortDelay write fHeaderRetrieveAbortDelay;
    /// how many invalid HTTP headers have been rejected
    property StatHeaderErrors: integer index grError read GetStat;
    /// how many invalid HTTP headers raised an exception
    property StatHeaderException: integer index grException read GetStat;
    /// how many HTTP requests pushed more than MaximumAllowedContentLength bytes
    property StatOversizedPayloads: integer index grOversizedPayload read GetStat;
    /// how many HTTP requests were rejected by the OnBeforeBody event handler
    property StatRejected: integer index grRejected read GetStat;
    /// how many HTTP requests were rejected after HeaderRetrieveAbortDelay timeout
    property StatHeaderTimeout: integer index grTimeout read GetStat;
    /// how many HTTP headers have been processed
    property StatHeaderProcessed: integer index grHeaderReceived read GetStat;
    /// how many HTTP bodies have been processed
    property StatBodyProcessed: integer index grBodyReceived read GetStat;
    /// how many HTTP connections were passed to an asynchronous handler
    // - e.g. for background WebSockets processing after proper upgrade
    property StatOwnedConnections: integer index grOwned read GetStat;
  end;


implementation


{ ******************** Shared Server-Side HTTP Process }

{ THttpServerRequest }

constructor THttpServerRequest.Create(aServer: THttpServerGeneric;
  aConnectionID: THttpServerConnectionID; aConnectionThread: TSynThread);
begin
  inherited Create;
  fServer := aServer;
  fConnectionID := aConnectionID;
  fConnectionThread := aConnectionThread;
end;

var
  GlobalRequestID: integer;

procedure THttpServerRequest.Prepare(const aURL, aMethod, aInHeaders: RawUTF8;
  const aInContent: RawByteString; const aInContentType, aRemoteIP: RawUTF8;
  aUseSSL: boolean);
var
  id: PInteger;
begin
  if fServer = nil then
    id := @GlobalRequestID
  else
    id := @fServer.fCurrentRequestID;
  fRequestID := InterLockedIncrement(id^);
  if fRequestID = maxInt - 2048 then // ensure no overflow (31-bit range)
    id^ := 0;
  fUseSSL := aUseSSL;
  fURL := aURL;
  fMethod := aMethod;
  fRemoteIP := aRemoteIP;
  if aRemoteIP <> '' then
    if aInHeaders = '' then
      fInHeaders := 'RemoteIP: ' + aRemoteIP
    else
      fInHeaders := aInHeaders + #13#10'RemoteIP: ' + aRemoteIP
  else
    fInHeaders := aInHeaders;
  fInContent := aInContent;
  fInContentType := aInContentType;
  fOutContent := '';
  fOutContentType := '';
  fOutCustomHeaders := '';
end;

procedure THttpServerRequest.AddInHeader(additionalHeader: RawUTF8);
begin
  additionalHeader := Trim(additionalHeader);
  if additionalHeader <> '' then
    if fInHeaders = '' then
      fInHeaders := additionalHeader
    else
      fInHeaders := fInHeaders + #13#10 + additionalHeader;
end;


{ TServerGeneric }

constructor TServerGeneric.Create(CreateSuspended: boolean;
  const OnStart, OnStop: TNotifyThreadEvent; const ProcessName: RawUTF8);
begin
  fProcessName := ProcessName;
  fOnHttpThreadStart := OnStart;
  SetOnTerminate(OnStop);
  inherited Create(CreateSuspended);
end;

procedure TServerGeneric.NotifyThreadStart(Sender: TSynThread);
begin
  if Sender = nil then
    raise EHttpServer.CreateUTF8('%.NotifyThreadStart(nil)', [self]);
  if Assigned(fOnHttpThreadStart) and not Assigned(Sender.StartNotified) then
  begin
    fOnHttpThreadStart(Sender);
    Sender.StartNotified := self;
  end;
end;

procedure TServerGeneric.SetOnTerminate(const Event: TNotifyThreadEvent);
begin
  fOnThreadTerminate := Event;
end;


{ THttpServerGeneric }

constructor THttpServerGeneric.Create(CreateSuspended: boolean;
  const OnStart, OnStop: TNotifyThreadEvent; const ProcessName: RawUTF8);
begin
  SetServerName('mORMot (' + OS_TEXT + ')');
  inherited Create(CreateSuspended, OnStart, OnStop, ProcessName);
end;

procedure THttpServerGeneric.RegisterCompress(aFunction: THttpSocketCompress;
  aCompressMinSize: integer);
begin
  RegisterCompressFunc(fCompress, aFunction, fCompressAcceptEncoding, aCompressMinSize);
end;

procedure THttpServerGeneric.Shutdown;
begin
  if self <> nil then
    fShutdownInProgress := true;
end;

function THttpServerGeneric.Request(Ctxt: THttpServerRequest): cardinal;
begin
  if (self = nil) or fShutdownInProgress then
    result := HTTP_NOTFOUND
  else
  begin
    NotifyThreadStart(Ctxt.ConnectionThread);
    if Assigned(OnRequest) then
      result := OnRequest(Ctxt)
    else
      result := HTTP_NOTFOUND;
  end;
end;

function THttpServerGeneric.Callback(Ctxt: THttpServerRequest; aNonBlocking:
  boolean): cardinal;
begin
  raise EHttpServer.CreateUTF8('%.Callback is not implemented: try to use ' +
    'another communication protocol, e.g. WebSockets', [self]);
end;

procedure THttpServerGeneric.SetServerName(const aName: RawUTF8);
begin
  fServerName := aName;
end;

procedure THttpServerGeneric.SetOnRequest(const aRequest: TOnHttpServerRequest);
begin
  fOnRequest := aRequest;
end;

procedure THttpServerGeneric.SetOnBeforeBody(const aEvent: TOnHttpServerBeforeBody);
begin
  fOnBeforeBody := aEvent;
end;

procedure THttpServerGeneric.SetOnBeforeRequest(const aEvent: TOnHttpServerRequest);
begin
  fOnBeforeRequest := aEvent;
end;

procedure THttpServerGeneric.SetOnAfterRequest(const aEvent: TOnHttpServerRequest);
begin
  fOnAfterRequest := aEvent;
end;

procedure THttpServerGeneric.SetOnAfterResponse(const aEvent: TOnHttpServerAfterResponse);
begin
  fOnAfterResponse := aEvent;
end;

function THttpServerGeneric.DoBeforeRequest(Ctxt: THttpServerRequest): cardinal;
begin
  if Assigned(fOnBeforeRequest) then
    result := fOnBeforeRequest(Ctxt)
  else
    result := 0;
end;

function THttpServerGeneric.DoAfterRequest(Ctxt: THttpServerRequest): cardinal;
begin
  if Assigned(fOnAfterRequest) then
    result := fOnAfterRequest(Ctxt)
  else
    result := 0;
end;

procedure THttpServerGeneric.DoAfterResponse(Ctxt: THttpServerRequest;
  const Code: cardinal);
begin
  if Assigned(fOnAfterResponse) then
    fOnAfterResponse(Ctxt, Code);
end;

procedure THttpServerGeneric.SetMaximumAllowedContentLength(aMax: cardinal);
begin
  fMaximumAllowedContentLength := aMax;
end;

procedure THttpServerGeneric.SetRemoteIPHeader(const aHeader: RawUTF8);
begin
  fRemoteIPHeader := aHeader;
  fRemoteIPHeaderUpper := UpperCase(aHeader);
end;

procedure THttpServerGeneric.SetRemoteConnIDHeader(const aHeader: RawUTF8);
begin
  fRemoteConnIDHeader := aHeader;
  fRemoteConnIDHeaderUpper := UpperCase(aHeader);
end;

function THttpServerGeneric.NextConnectionID: integer;
begin
  result := InterlockedIncrement(fCurrentConnectionID);
  if result = maxInt - 2048 then // paranoid 31-bit counter reset to ensure >0
    fCurrentConnectionID := 0;
end;


{ ******************** THttpServerSocket/THttpServer HTTP/1.1 Server }

{ THttpServer }

constructor THttpServer.Create(const aPort: RawUTF8;
  const OnStart, OnStop: TNotifyThreadEvent; const ProcessName: RawUTF8;
  ServerThreadPoolCount, KeepAliveTimeOut: integer;
  HeadersUnFiltered, CreateSuspended: boolean);
begin
  fSockPort := aPort;
  fInternalHttpServerRespList := {$ifdef FPC}TFPList{$else}TList{$endif}.Create;
  InitializeCriticalSection(fProcessCS);
  fServerKeepAliveTimeOut := KeepAliveTimeOut; // 30 seconds by default
  if fThreadPool <> nil then
    fThreadPool.ContentionAbortDelay := 5000; // 5 seconds default
  // event handlers set before inherited Create to be visible in childs
  fOnHttpThreadStart := OnStart;
  SetOnTerminate(OnStop);
  if fThreadRespClass = nil then
    fThreadRespClass := THttpServerResp;
  if fSocketClass = nil then
    fSocketClass := THttpServerSocket;
  if ServerThreadPoolCount > 0 then
  begin
    fThreadPool := TSynThreadPoolTHttpServer.Create(self, ServerThreadPoolCount);
    fHTTPQueueLength := 1000;
  end;
  fHeadersNotFiltered := HeadersUnFiltered;
  inherited Create(CreateSuspended, OnStart, OnStop, ProcessName);
end;

function THttpServer.GetAPIVersion: RawUTF8;
begin
  result := SocketAPIVersion;
end;

destructor THttpServer.Destroy;
var
  endtix: Int64;
  i: integer;
  resp: THttpServerResp;
  callback: TNetSocket;
begin
  Terminate; // set Terminated := true for THttpServerResp.Execute
  if fThreadPool <> nil then
    fThreadPool.fTerminated := true; // notify background process
  if (fExecuteState = esRunning) and (Sock <> nil) then
  begin
    Sock.Close; // shutdown the socket to unlock Accept() in Execute
    if NewSocket('127.0.0.1', Sock.Port, nlTCP, false, 1, 1, 1, 0, callback) = nrOK then
      callback.ShutdownAndClose({rdwr=}false);
  end;
  endtix := mormot.core.os.GetTickCount64 + 20000;
  EnterCriticalSection(fProcessCS);
  try
    if fInternalHttpServerRespList <> nil then
    begin
      for i := 0 to fInternalHttpServerRespList.Count - 1 do
      begin
        resp := fInternalHttpServerRespList.List[i];
        resp.Terminate;
        resp.fServerSock.Sock.ShutdownAndClose({rdwr=}true);
      end;
      repeat // wait for all THttpServerResp.Execute to be finished
        if (fInternalHttpServerRespList.Count = 0) and (fExecuteState <> esRunning) then
          break;
        LeaveCriticalSection(fProcessCS);
        SleepHiRes(100);
        EnterCriticalSection(fProcessCS);
      until mormot.core.os.GetTickCount64 > endtix;
      FreeAndNil(fInternalHttpServerRespList);
    end;
  finally
    LeaveCriticalSection(fProcessCS);
    FreeAndNil(fThreadPool); // release all associated threads and I/O completion
    FreeAndNil(fSock);
    inherited Destroy;       // direct Thread abort, no wait till ended
    DeleteCriticalSection(fProcessCS);
  end;
end;

function THttpServer.GetStat(one: THttpServerSocketGetRequestResult): integer;
begin
  result := fStats[one];
end;

function THttpServer.GetHTTPQueueLength: Cardinal;
begin
  result := fHTTPQueueLength;
end;

procedure THttpServer.SetHTTPQueueLength(aValue: Cardinal);
begin
  fHTTPQueueLength := aValue;
end;

procedure THttpServer.InternalHttpServerRespListAdd(resp: THttpServerResp);
begin
  if (self = nil) or (fInternalHttpServerRespList = nil) or (resp = nil) then
    exit;
  EnterCriticalSection(fProcessCS);
  try
    fInternalHttpServerRespList.Add(resp);
  finally
    LeaveCriticalSection(fProcessCS);
  end;
end;

procedure THttpServer.InternalHttpServerRespListRemove(resp: THttpServerResp);
var
  i: integer;
begin
  if (self = nil) or (fInternalHttpServerRespList = nil) then
    exit;
  EnterCriticalSection(fProcessCS);
  try
    i := fInternalHttpServerRespList.IndexOf(resp);
    if i >= 0 then
      fInternalHttpServerRespList.Delete(i);
  finally
    LeaveCriticalSection(fProcessCS);
  end;
end;

function THttpServer.OnNginxAllowSend(Context: THttpServerRequest;
  const LocalFileName: TFileName): boolean;
var
  match, i, f: PtrInt;
  folder: ^TFileName;
begin
  match := 0;
  folder := pointer(fNginxSendFileFrom);
  if LocalFileName <> '' then
    for f := 1 to length(fNginxSendFileFrom) do
    begin
      match := length(folder^);
      for i := 1 to match do // case sensitive left search
        if LocalFileName[i] <> folder^[i] then
        begin
          match := 0;
          break;
        end;
      if match <> 0 then
        break; // found matching folder
      inc(folder);
    end;
  result := match <> 0;
  if not result then
    exit; // no match -> manual send
  delete(Context.fOutContent, 1, match); // remove e.g. '/var/www'
  Context.OutCustomHeaders := Trim(Context.OutCustomHeaders + #13#10 +
    'X-Accel-Redirect: ' + Context.OutContent);
  Context.OutContent := '';
end;

procedure THttpServer.NginxSendFileFrom(const FileNameLeftTrim: TFileName);
var
  n: PtrInt;
begin
  n := length(fNginxSendFileFrom);
  SetLength(fNginxSendFileFrom, n + 1);
  fNginxSendFileFrom[n] := FileNameLeftTrim;
  fOnSendFile := OnNginxAllowSend;
end;

procedure THttpServer.WaitStarted(Seconds: integer);
var
  tix: Int64;
  ok: boolean;
begin
  tix := mormot.core.os.GetTickCount64 + Seconds * 1000; // never wait forever
  repeat
    EnterCriticalSection(fProcessCS);
    ok := Terminated or (fExecuteState in [esRunning, esFinished]);
    LeaveCriticalSection(fProcessCS);
    if ok then
      exit;
    Sleep(1);
    if mormot.core.os.GetTickCount64 > tix then
      raise EHttpServer.CreateUTF8('%.WaitStarted failed after % seconds [%]',
        [self, Seconds, fExecuteMessage]);
  until false;
end;

{.$define MONOTHREAD}
// define this not to create a thread at every connection (not recommended)

procedure THttpServer.Execute;
var
  ClientSock: TNetSocket;
  ClientSin: TNetAddr;
  ClientCrtSock: THttpServerSocket;
  res: TNetResult;
  {$ifdef MONOTHREAD}
  endtix: Int64;
  {$endif}
begin
  // THttpServerGeneric thread preparation: launch any OnHttpThreadStart event
  fExecuteState := esBinding;
  NotifyThreadStart(self);
  // main server process loop
  try
    fSock := TCrtSocket.Bind(fSockPort); // BIND + LISTEN
    {$ifdef LINUXNOTBSD}
    // in case we started by systemd, listening socket is created by another process
    // and do not interrupt while process got a signal. So we need to set a timeout to
    // unblock accept() periodically and check we need terminations
    if fSockPort = '' then // external socket
      fSock.ReceiveTimeout := 1000; // unblock accept every second
    {$endif LINUXNOTBSD}
    fExecuteState := esRunning;
    if not fSock.SockIsDefined then // paranoid (Bind would have raise an exception)
      raise EHttpServer.CreateUTF8('%.Execute: %.Bind failed', [self, fSock]);
    while not Terminated do
    begin
      res := Sock.Sock.Accept(ClientSock, ClientSin);
      if not (res in [nrOK, nrRetry]) then
        if Terminated then
          break
        else
        begin
          SleepHiRes(1); // failure (too many clients?) -> wait and retry
          continue;
        end;
      if Terminated or (Sock = nil) then
      begin
        ClientSock.ShutdownAndClose({rdwr=}true);
        break; // don't accept input if server is down
      end;
      OnConnect;
      {$ifdef MONOTHREAD}
      ClientCrtSock := fSocketClass.Create(self);
      try
        ClientCrtSock.InitRequest(ClientSock);
        endtix := fHeaderRetrieveAbortDelay;
        if endtix > 0 then
          inc(endtix, mormot.core.os.GetTickCount64);
        if ClientCrtSock.GetRequest({withbody=}true, endtix)
            in [grBodyReceived, grHeaderReceived] then
          Process(ClientCrtSock, 0, self);
        OnDisconnect;
        DirectShutdown(ClientSock);
      finally
        ClientCrtSock.Free;
      end;
      {$else}
      if Assigned(fThreadPool) then
      begin
        // use thread pool to process the request header, and probably its body
        ClientCrtSock := fSocketClass.Create(self);
        ClientCrtSock.AcceptRequest(ClientSock, @ClientSin);
        if not fThreadPool.Push(pointer(PtrUInt(ClientCrtSock)),
          {waitoncontention=}true) then
        begin
          // returned false if there is no idle thread in the pool, and queue is full
          ClientCrtSock.Free; // will call DirectShutdown(ClientSock)
        end;
      end
      else
        // default implementation creates one thread for each incoming socket
        fThreadRespClass.Create(ClientSock, ClientSin, self);
      {$endif MONOTHREAD}
    end;
  except
    on E: Exception do // any exception would break and release the thread
      fExecuteMessage := E.ClassName + ' [' + E.Message + ']';
  end;
  EnterCriticalSection(fProcessCS);
  fExecuteState := esFinished;
  LeaveCriticalSection(fProcessCS);
end;

procedure THttpServer.OnConnect;
begin
  InterLockedIncrement(fServerConnectionCount);
  InterLockedIncrement(fServerConnectionActive);
end;

procedure THttpServer.OnDisconnect;
begin
  InterLockedDecrement(fServerConnectionActive);
end;

function IdemPCharNotVoid(p: PByteArray; up: PByte; toup: PByteArray): boolean;
  {$ifdef HASINLINE} inline;{$endif}
var
  u: byte;
begin
  // slightly more efficient than plain IdemPChar() - we don't check p/up=nil
  result := false;
  dec(PtrUInt(p), PtrUInt(up));
  repeat
    u := up^;
    if u = 0 then
      break;
    if toup[p[PtrUInt(up)]] <> u then
      exit;
    inc(up);
  until false;
  result := true;
end;

procedure ExtractNameValue(var headers: RawUTF8; const upname: RawUTF8; out res: RawUTF8);
var
  i, j, k: PtrInt;
begin
  if (headers = '') or (upname = '') then
    exit;
  i := 1;
  repeat
    k := length(headers) + 1;
    for j := i to k - 1 do
      if headers[j] < ' ' then
      begin
        k := j;
        break;
      end;
    if IdemPCharNotVoid(@PByteArray(headers)[i - 1], pointer(upname), @NormToUpper) then
    begin
      j := i;
      inc(i, length(upname));
      TrimCopy(headers, i, k - i, res);
      while true do // delete also ending #13#10
        if (headers[k] = #0) or (headers[k] >= ' ') then
          break
        else
          inc(k);
      delete(headers, j, k - j);
      exit;
    end;
    i := k;
    while headers[i] < ' ' do
      if headers[i] = #0 then
        exit
      else
        inc(i);
  until false;
end;

procedure THttpServer.Process(ClientSock: THttpServerSocket;
  ConnectionID: THttpServerConnectionID; ConnectionThread: TSynThread);
var
  ctxt: THttpServerRequest;
  P: PUTF8Char;
  respsent: boolean;
  Code, afterCode: cardinal;
  s, reason: RawUTF8;
  ErrorMsg: string;

  function SendResponse: boolean;
  var
    fs: TFileStream;
    fn: TFileName;
  begin
    result := not Terminated; // true=success
    if not result then
      exit;
    {$ifdef SYNCRTDEBUGLOW}
    TSynLog.Add.Log(sllCustom2, 'SendResponse respsent=% code=%', [respsent,
      Code], self);
    {$endif}
    respsent := true;
    // handle case of direct sending of static file (as with http.sys)
    if (ctxt.OutContent <> '') and (ctxt.OutContentType = STATICFILE_CONTENT_TYPE) then
    try
      ExtractNameValue(ctxt.fOutCustomHeaders, 'CONTENT-TYPE:', ctxt.fOutContentType);
      {$ifdef UNICODE}
      fn := UTF8ToUnicodeString(ctxt.OutContent);
      {$else}
      fn := Utf8ToAnsi(ctxt.OutContent);
      {$endif UNICODE}
      if not Assigned(fOnSendFile) or not fOnSendFile(ctxt, fn) then
      begin
        fs := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);
        try
          SetString(ctxt.fOutContent, nil, fs.Size);
          fs.Read(Pointer(ctxt.fOutContent)^, length(ctxt.fOutContent));
        finally
          fs.Free;
        end;
      end;
    except
      on E: Exception do
      begin // error reading or sending file
        ErrorMsg := E.ClassName + ': ' + E.Message;
        Code := HTTP_NOTFOUND;
        result := false; // fatal error
      end;
    end;
    if ctxt.OutContentType = NORESPONSE_CONTENT_TYPE then
      ctxt.OutContentType := ''; // true HTTP always expects a response
    // send response (multi-thread OK) at once
    if (Code < HTTP_SUCCESS) or (ClientSock.Headers = '') then
      Code := HTTP_NOTFOUND;
    reason := StatusCodeToReason(Code);
    if ErrorMsg <> '' then
    begin
      ctxt.OutCustomHeaders := '';
      ctxt.OutContentType := 'text/html; charset=utf-8'; // create message to display
      ctxt.OutContent := FormatUTF8('<body style="font-family:verdana">'#10 +
        '<h1>% Server Error %</h1><hr><p>HTTP % %<p>%<p><small>%',
        [self, Code, Code, reason, HtmlEscape(ErrorMsg), fServerName]);
    end;
    // 1. send HTTP status command
    if ClientSock.TCPPrefix <> '' then
      ClientSock.SockSend(ClientSock.TCPPrefix);
    if ClientSock.KeepAliveClient then
      ClientSock.SockSend(['HTTP/1.1 ', Code, ' ', reason])
    else
      ClientSock.SockSend(['HTTP/1.0 ', Code, ' ', reason]);
    // 2. send headers
    // 2.1. custom headers from Request() method
    P := pointer(ctxt.fOutCustomHeaders);
    while P <> nil do
    begin
      s := GetNextLine(P, {next=}P);
      if s <> '' then
      begin // no void line (means headers ending)
        ClientSock.SockSend(s);
        if IdemPChar(pointer(s), 'CONTENT-ENCODING:') then
          // custom encoding: don't compress
          integer(ClientSock.fCompressAcceptHeader) := 0;
      end;
    end;
    // 2.2. generic headers
    ClientSock.SockSend([
      {$ifndef NOXPOWEREDNAME}
      XPOWEREDNAME + ': ' + XPOWEREDVALUE + #13#10 +
      {$endif NOXPOWEREDNAME}
      'Server: ', fServerName]);
    ClientSock.CompressDataAndWriteHeaders(ctxt.OutContentType, ctxt.fOutContent);
    if ClientSock.KeepAliveClient then
    begin
      if ClientSock.fCompressAcceptEncoding <> '' then
        ClientSock.SockSend(ClientSock.fCompressAcceptEncoding);
      ClientSock.SockSend('Connection: Keep-Alive'#13#10); // #13#10 -> end headers
    end
    else
      ClientSock.SockSend; // headers must end with a void line
    // 3. sent HTTP body content (if any)
    ClientSock.SockSendFlush(ctxt.OutContent); // flush all data to network
  end;

begin
  if (ClientSock = nil) or (ClientSock.Headers = '') then
    // we didn't get the request = socket read error
    exit; // -> send will probably fail -> nothing to send back
  if Terminated then
    exit;
  ctxt := THttpServerRequest.Create(self, ConnectionID, ConnectionThread);
  try
    respsent := false;
    with ClientSock do
      ctxt.Prepare(URL, Method, HeaderGetText(fRemoteIP), Content, ContentType,
        '', ClientSock.fTLS);
    try
      Code := DoBeforeRequest(ctxt);
      {$ifdef SYNCRTDEBUGLOW}
      TSynLog.Add.Log(sllCustom2, 'DoBeforeRequest=%', [Code], self);
      {$endif}
      if Code > 0 then
        if not SendResponse or (Code <> HTTP_ACCEPTED) then
          exit;
      Code := Request(ctxt);
      afterCode := DoAfterRequest(ctxt);
      {$ifdef SYNCRTDEBUGLOW}
      TSynLog.Add.Log(sllCustom2, 'Request=% DoAfterRequest=%', [Code, afterCode], self);
      {$endif}
      if afterCode > 0 then
        Code := afterCode;
      if respsent or SendResponse then
        DoAfterResponse(ctxt, Code);
      {$ifdef SYNCRTDEBUGLOW}
      TSynLog.Add.Log(sllCustom2, 'DoAfterResponse respsent=% ErrorMsg=%',
        [respsent, ErrorMsg], self);
      {$endif}
    except
      on E: Exception do
        if not respsent then
        begin
          ErrorMsg := E.ClassName + ': ' + E.Message;
          Code := HTTP_SERVERERROR;
          SendResponse;
        end;
    end;
  finally
    if Sock <> nil then
    begin // add transfert stats to main socket
      EnterCriticalSection(fProcessCS);
      Sock.BytesIn := Sock.BytesIn + ClientSock.BytesIn;
      Sock.BytesOut := Sock.BytesOut + ClientSock.BytesOut;
      LeaveCriticalSection(fProcessCS);
      ClientSock.fBytesIn := 0;
      ClientSock.fBytesOut := 0;
    end;
    ctxt.Free;
  end;
end;


{ THttpServerSocket }

constructor THttpServerSocket.Create(aServer: THttpServer);
begin
  inherited Create(5000);
  if aServer <> nil then // nil e.g. from TRTSPOverHTTPServer
  begin
    fServer := aServer;
    fCompress := aServer.fCompress;
    fCompressAcceptEncoding := aServer.fCompressAcceptEncoding;
    fSocketLayer := aServer.Sock.SocketLayer;
    TCPPrefix := aServer.TCPPrefix;
  end;
end;

function THttpServerSocket.GetRequest(withBody: boolean; headerMaxTix: Int64):
  THttpServerSocketGetRequestResult;
var
  P: PUTF8Char;
  status: cardinal;
  pending: integer;
  reason, allheaders: RawUTF8;
  noheaderfilter: boolean;
begin
  result := grError;
  try
    // use SockIn with 1KB buffer if not already initialized: 2x faster
    CreateSockIn;
    // abort now with no exception if socket is obviously broken
    if fServer <> nil then
    begin
      pending := SockInPending(100, {alsosocket=}true);
      if (pending < 0) or (fServer = nil) or fServer.Terminated then
        exit;
      noheaderfilter := fServer.HeadersNotFiltered;
    end
    else
      noheaderfilter := false;
    // 1st line is command: 'GET /path HTTP/1.1' e.g.
    SockRecvLn(Command);
    if TCPPrefix <> '' then
      if TCPPrefix <> Command then
        exit
      else
        SockRecvLn(Command);
    P := pointer(Command);
    if P = nil then
      exit; // broken
    GetNextItem(P, ' ', fMethod); // 'GET'
    GetNextItem(P, ' ', fURL);    // '/path'
    fKeepAliveClient := ((fServer = nil) or (fServer.ServerKeepAliveTimeOut > 0))
      and IdemPChar(P, 'HTTP/1.1');
    Content := '';
    // get headers and content
    GetHeader(noheaderfilter);
    if fServer <> nil then
    begin // nil from TRTSPOverHTTPServer
      if fServer.fRemoteIPHeaderUpper <> '' then
        // real Internet IP (replace 127.0.0.1 from a proxy)
        FindNameValue(headers, pointer(fServer.fRemoteIPHeaderUpper), fRemoteIP,
          {keepnotfound=}true);
      if fServer.fRemoteConnIDHeaderUpper <> '' then
      begin
        P := FindNameValue(pointer(headers), pointer(fServer.fRemoteConnIDHeaderUpper));
        if P <> nil then
          SetQWord(P, PQWord(@fRemoteConnectionID)^);
      end;
    end;
    if connectionClose in HeaderFlags then
      fKeepAliveClient := false;
    if (ContentLength < 0) and (KeepAliveClient or (fMethod = 'GET')) then
      ContentLength := 0; // HTTP/1.1 and no content length -> no eof
    if (headerMaxTix > 0) and (GetTickCount64 > headerMaxTix) then
    begin
      result := grTimeout;
      exit; // allow 10 sec for header -> DOS/TCPSYN Flood
    end;
    if fServer <> nil then
    begin
      if (ContentLength > 0) and (fServer.MaximumAllowedContentLength > 0) and
         (cardinal(ContentLength) > fServer.MaximumAllowedContentLength) then
      begin
        SockSend('HTTP/1.0 413 Payload Too Large'#13#10#13#10'Rejected');
        SockSendFlush('');
        result := grOversizedPayload;
        exit;
      end;
      if Assigned(fServer.OnBeforeBody) then
      begin
        allheaders := HeaderGetText(fRemoteIP);
        status := fServer.OnBeforeBody(fURL, fMethod, allheaders, ContentType,
          RemoteIP, ContentLength, false);
        {$ifdef SYNCRTDEBUGLOW}
        TSynLog.Add.Log(sllCustom2,
          'GetRequest sock=% OnBeforeBody=% Command=% Headers=%', [fSock, status,
          LogEscapeFull(Command), LogEscapeFull(allheaders)], self);
        TSynLog.Add.Log(sllCustom2, 'GetRequest OnBeforeBody headers', TypeInfo(TSockStringDynArray),
          headers, self);
        {$endif}
        if status <> HTTP_SUCCESS then
        begin
          reason := StatusCodeToReason(status);
          SockSend(['HTTP/1.0 ', status, ' ', reason, #13#10#13#10, reason, ' ', status]);
          SockSendFlush('');
          result := grRejected;
          exit;
        end;
      end;
    end;
    if withBody and not (connectionUpgrade in HeaderFlags) then
    begin
      GetBody;
      result := grBodyReceived;
    end
    else
      result := grHeaderReceived;
  except
    on E: Exception do
      result := grException;
  end;
end;


{ THttpServerResp }

constructor THttpServerResp.Create(aSock: TNetSocket; const aSin: TNetAddr;
  aServer: THttpServer);
var
  c: THttpServerSocketClass;
begin
  fClientSock := aSock;
  fClientSin := aSin;
  if aServer = nil then
    c := THttpServerSocket
  else
    c := aServer.fSocketClass;
  Create(c.Create(aServer), aServer); // on Linux, Execute raises during Create
end;

constructor THttpServerResp.Create(aServerSock: THttpServerSocket; aServer: THttpServer);
begin
  fServer := aServer;
  fServerSock := aServerSock;
  fOnThreadTerminate := fServer.fOnThreadTerminate;
  fServer.InternalHttpServerRespListAdd(self);
  fConnectionID := aServerSock.RemoteConnectionID;
  if fConnectionID = 0 then
    fConnectionID := fServer.NextConnectionID; // fallback to 31-bit sequence
  FreeOnTerminate := true;
  inherited Create(false);
end;

procedure THttpServerResp.Execute;

  procedure HandleRequestsProcess;
  var
    keepaliveendtix, beforetix, headertix, tix: Int64;
    pending: TCrtSocketPending;
    res: THttpServerSocketGetRequestResult;
  begin
    {$ifdef SYNCRTDEBUGLOW} try {$endif}
    try
      repeat
        beforetix := mormot.core.os.GetTickCount64;
        keepaliveendtix := beforetix + fServer.ServerKeepAliveTimeOut;
        repeat
          // within this loop, break=wait for next command, exit=quit
          if (fServer = nil) or fServer.Terminated or (fServerSock = nil) then
            // server is down -> close connection
            exit;
          pending := fServerSock.SockReceivePending(50); // 50 ms timeout
          if (fServer = nil) or fServer.Terminated then
            // server is down -> disconnect the client
            exit;
          {$ifdef SYNCRTDEBUGLOW}
          TSynLog.Add.Log(sllCustom2,
            'HandleRequestsProcess: sock=% pending=%', [fServerSock.fSock,
            _CSP[pending]], self);
          {$endif}
          case pending of
            cspSocketError:
              exit; // socket error -> disconnect the client
            cspNoData:
              begin
                tix := mormot.core.os.GetTickCount64;
                if tix >= keepaliveendtix then
                  exit; // reached keep alive time out -> close connection
                if tix - beforetix < 40 then
                begin
                  {$ifdef SYNCRTDEBUGLOW}
                  // getsockopt(fServerSock.fSock,SOL_SOCKET,SO_ERROR,@error,errorlen) returns 0 :(
                  TSynLog.Add.Log(sllCustom2, 'HandleRequestsProcess: sock=% LOWDELAY=%',
                    [fServerSock.fSock, tix - beforetix], self);
                  {$endif}
                  SleepHiRes(1); // seen only on Windows in practice
                  if (fServer = nil) or fServer.Terminated then
                    // server is down -> disconnect the client
                    exit;
                end;
                beforetix := tix;
              end;
            cspDataAvailable:
              begin
                // get request and headers
                headertix := fServer.HeaderRetrieveAbortDelay;
                if headertix > 0 then
                  inc(headertix, beforetix);
                res := fServerSock.GetRequest({withbody=}true, headertix);
                if (fServer = nil) or fServer.Terminated then
                  // server is down -> disconnect the client
                  exit;
                InterLockedIncrement(fServer.fStats[res]);
                case res of
                  grBodyReceived, grHeaderReceived:
                    begin
                      if res = grBodyReceived then
                        InterlockedIncrement(fServer.fStats[grHeaderReceived]);
                      // calc answer and send response
                      fServer.Process(fServerSock, ConnectionID, self);
                      // keep connection only if necessary
                      if fServerSock.KeepAliveClient then
                        break
                      else
                        exit;
                    end;
                  grOwned:
                    begin
                      fServerSock := nil; // will be freed by new owner
                      exit;
                    end;
                else
                  // fServerSock connection was down or headers are not correct
                  exit;
                end;
              end;
          end;
        until false;
      until false;
    except
      on E: Exception do
        ; // any exception will silently disconnect the client
    end;
    {$ifdef SYNCRTDEBUGLOW}
    finally
      TSynLog.Add.Log(sllCustom2, 'HandleRequestsProcess: close sock=%', [fServerSock.fSock],
        self);
    end;
    {$endif}
  end;

var
  aSock: TNetSocket;
begin
  fServer.NotifyThreadStart(self);
  try
    try
      if fClientSock.Socket <> 0 then
      begin
        // direct call from incoming socket
        aSock := fClientSock;
        fClientSock := nil; // fServerSock owns fClientSock
        fServerSock.AcceptRequest(aSock, @fClientSin);
        if fServer <> nil then
          HandleRequestsProcess;
      end
      else
      begin
        // call from TSynThreadPoolTHttpServer -> handle first request
        if not fServerSock.fBodyRetrieved then
          fServerSock.GetBody;
        fServer.Process(fServerSock, ConnectionID, self);
        if (fServer <> nil) and fServerSock.KeepAliveClient then
          HandleRequestsProcess; // process further kept alive requests
      end;
    finally
      try
        if fServer <> nil then
        try
          fServer.OnDisconnect;
        finally
          fServer.InternalHttpServerRespListRemove(self);
          fServer := nil;
        end;
      finally
        FreeAndNil(fServerSock);
        // if Destroy happens before fServerSock.GetRequest() in Execute below
        fClientSock.ShutdownAndClose({rdwr=}false);
      end;
    end;
  except
    on Exception do
      ; // just ignore unexpected exceptions here, especially during clean-up
  end;
end;


{ TSynThreadPoolTHttpServer }

constructor TSynThreadPoolTHttpServer.Create(Server: THttpServer;
  NumberOfThreads: Integer);
begin
  fServer := Server;
  fOnThreadTerminate := fServer.fOnThreadTerminate;
  inherited Create(NumberOfThreads {$ifndef USE_WINIOCP}, {queuepending=}true{$endif});
end;

{$ifndef USE_WINIOCP}
function TSynThreadPoolTHttpServer.QueueLength: integer;
begin
  if fServer = nil then
    result := 10000
  else
    result := fServer.fHTTPQueueLength;
end;
{$endif USE_WINIOCP}

procedure TSynThreadPoolTHttpServer.Task(aCaller: TSynThread; aContext: Pointer);
var
  ServerSock: THttpServerSocket;
  headertix: Int64;
  res: THttpServerSocketGetRequestResult;
begin
  ServerSock := aContext;
  try
    if fServer.Terminated then
      exit;
    // get Header of incoming request in the thread pool
    headertix := fServer.HeaderRetrieveAbortDelay;
    if headertix > 0 then
      headertix := headertix + GetTickCount64;
    res := ServerSock.GetRequest({withbody=}false, headertix);
    if (fServer = nil) or fServer.Terminated then
      exit;
    InterlockedIncrement(fServer.fStats[res]);
    case res of
      grHeaderReceived:
        begin
          // connection and header seem valid -> process request further
          if (fServer.ServerKeepAliveTimeOut > 0) and
             (fServer.fInternalHttpServerRespList.Count < THREADPOOL_MAXWORKTHREADS) and
             (ServerSock.KeepAliveClient or
              (ServerSock.ContentLength > THREADPOOL_BIGBODYSIZE)) then
          begin
            // HTTP/1.1 Keep Alive (including WebSockets) or posted data > 16 MB
            // -> process in dedicated background thread
            fServer.fThreadRespClass.Create(ServerSock, fServer);
            ServerSock := nil; // THttpServerResp will own and free ServerSock
          end
          else
          begin
            // no Keep Alive = multi-connection -> process in the Thread Pool
            if not (connectionUpgrade in ServerSock.HeaderFlags) then
            begin
              ServerSock.GetBody; // we need to get it now
              InterlockedIncrement(fServer.fStats[grBodyReceived]);
            end;
            // multi-connection -> process now
            fServer.Process(ServerSock, ServerSock.RemoteConnectionID, aCaller);
            fServer.OnDisconnect;
            // no Shutdown here: will be done client-side
          end;
        end;
      grOwned:
        // e.g. for asynchrounous WebSockets
        ServerSock := nil; // to ignore FreeAndNil(ServerSock) below
    end; // errors will close the connection
  finally
    FreeAndNil(ServerSock);
  end;
end;

procedure TSynThreadPoolTHttpServer.TaskAbort(aContext: Pointer);
begin
  THttpServerSocket(aContext).Free;
end;

initialization

finalization

end.

