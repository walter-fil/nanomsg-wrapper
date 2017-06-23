/**
    nanomsg is a socket library that provides several common communication patterns. It aims to make the networking layer fast, scalable, and easy to use.
    Implemented in C, it works on a wide range of operating systems with no further dependencies.

    This module implements a convenience wrapper API for nanomsg

    Authors: Laeeth Isharc and Atila Neves (Kaleidic Associates Advisory Limited)

    Example code:
        http://nanomsg.code.kaleidic.io/nanomsg.wrap.responder.html
        http://nanomsg.code.kaleidic.io/nanomsg.wrap.checkNanoSocket.html
        http://nanomsg.code.kaleidic.io/examples/nanomsg.examples.html

 */
module nanomsg.wrap;


import nanomsg.bindings;
public import std.typecons: Yes, No; // to facilitate using send, receive

version(unittest)
    import unit_threaded;
else
    enum HiddenTest;


/// wrapper for a string uri to connect to
struct ConnectTo {
    string uri;
}

/// wrapper for a string uri to bind to
struct BindTo {
    string uri;
}

/**

    NanoSocket - high level wrapper for a nanomsg socket

*/
struct NanoSocket {

    import std.traits: isArray;
    import std.typecons: Flag;
    import std.datetime: Duration;

    /// nanomsg protocol
    enum Protocol {
        request,
        response,
        subscribe,
        publish,
        pull,
        push,
        pair,
        surveyor,
        respondent,
        bus,
    }

    /// nanomsg socket options
    enum Option {
        lingerMs, /// How long to try and send pending messages after nn_close. -1 means infinite
        sendBufferSize, // Size of the send buffer in bytes
        receiveBufferSize, // Size of the receive buffer in bytes
        receiveMaxSize, /// Maximum message size that can be received, in bytes
        sendTimeoutMs, /// How long in milliseconds it takes for send to timeout
        receiveTimeoutMs, /// How long in milliseconds it takes for receive to timeout
        reconnectIntervalMs, /// How long to wait to re-establish connection
        reconnectIntervalMax, /// Maximum reconnect interval
        sendPriority, /// Outbound priority for endpoints added to socket
        receivePriority, /// Inbout priority for endpoints added to socket
        ipv4Only, /// Self-explanatory
        socketName, /// Socket name for error reporting and statistics
        timeToLive, /// Number of hops before message is dropped
        subscribeTopic, /// Subscribe to topic
        unsubscribeTopic, /// Unsubscribe to topic
        tcpNoDelay, /// Disables Nagle's algorithm
        surveyorDeadlineMs, /// How long to wait for responses in milliseconds
    }

    /// this(this) disabled to avoid sockets being destroyed
    @disable this(this);

    /// invalid FD
    enum INVALID_FD = -1;

    /// constructor
    this(Protocol protocol, int domain = AF_SP) @trusted {

        int protocolToInt(Protocol protocol) {
            final switch(protocol) with(Protocol) {
                case request:
                    return NN_REQ;
                case response:
                    return NN_REP;
                case publish:
                    return NN_PUB;
                case subscribe:
                    return NN_SUB;
                case pull:
                    return NN_PULL;
                case push:
                    return NN_PUSH;
                case pair:
                    return NN_PAIR;
                case surveyor:
                    return NN_SURVEYOR;
                case respondent:
                    return NN_RESPONDENT;
                case bus:
                    return NN_BUS;
            }
        }

        _nanoSock = nn_socket(domain, protocolToInt(protocol));
        _protocol = protocol;
        enforceNanoMsgRet(_nanoSock);
    }

    /// constructor
    this(in Protocol protocol, in BindTo bindTo, int domain = AF_SP) @trusted {
        import std.string: replace;

        this(protocol, domain);

        // this is so it's easy to specify the same string
        // for both ends of the socket
        bind(bindTo.uri.replace("localhost", "*"));
    }

    /// constructor
    this(in Protocol protocol, in ConnectTo connectTo, int domain = AF_SP) @trusted {

        this(protocol, domain);
        connect(connectTo.uri);

        version(Windows) {
            // on Windows sometimes the socket tries to send before the TCP handshake
            import core.thread;
            Thread.sleep(100.msecs);
        }
    }

    /// destructor
    ~this() @safe nothrow {
        close;
    }

    /// close socket
    void close() @trusted nothrow {
        if(_nanoSock != INVALID_FD) {
            _nanoSock.nn_close;
        }
    }

    /// set socket option to a value
    ref inout(NanoSocket) setOption(T)(Option option, T val) inout {
        const optionC = toOptionC(option);
        setOption(optionC.level, optionC.option, val);
        return this;
    }

    /// get socket option value
    T getOption(T)(Option option) const {
        const optionC = toOptionC(option);
        return getOption!T(optionC.level, optionC.option);
    }

    /// receive
    ubyte[] receive(int BUF_SIZE = 1024)(Flag!"blocking" blocking = Yes.blocking) const {
        import std.exception: enforce;
        import std.conv: text;
        import core.stdc.errno: EAGAIN, EINTR;

        ubyte[BUF_SIZE] buf;
        const flags = blocking ? 0 : NN_DONTWAIT;
        const numBytes = nn_recv(_nanoSock, buf.ptr, buf.length, flags);

        if(blocking) enforceNanoMsgRet(numBytes);

        return numBytes >= 0 ? buf[0 .. numBytes].dup : [];
    }

    /**
       Sends the bytes as expected. If the protocol is Request, then returns
       the response, otherwise returns an empty array.
     */
    ubyte[] send(T)(T[] data, Flag!"blocking" blocking = Yes.blocking) const {
        import std.exception: enforce;
        import std.conv: text;

        const sent = nn_send(_nanoSock, data.ptr, data.length, flags(blocking));
        if(blocking)
            enforce(sent == data.length,
                    text("Expected to send ", data.length, " bytes but sent ", sent));

        return _protocol == Protocol.request ? receive(blocking) : [];

    }

    /**
     Tries to send bytes to the other side.
     duration is how long to try for
     recvBlocking controls whether or not to block on reception of a response.
     This only matters when the protocol is request/response
     Returns the response if in request mode, otherwise an empty byte slice.
     */
    ubyte[] trySend(T)(T[] data, Duration duration, Flag!"blocking" recvBlocking = Yes.blocking) {
        import std.exception: enforce;
        import std.datetime: StopWatch, AutoStart, msecs;
        import std.conv: text;
        import core.thread: Thread;

        int sent;
        auto sw = StopWatch(AutoStart.yes);
        do {
            sent = nn_send(_nanoSock, data.ptr, data.length, flags(No.blocking));
            if(sent != data.length) Thread.sleep(10.msecs); // play nice with other threads and the CPU
        } while(sent != data.length && cast(Duration)sw.peek < duration);

        enforce(sent == data.length,
                text("Expected to send ", data.length, " bytes but sent ", sent));

        return _protocol == Protocol.request ? receive(recvBlocking) : [];
    }

    /// connect
    void connect(in string uri, in string file = __FILE__, in size_t line = __LINE__) {
        import std.string: toStringz;
        enforceNanoMsgRet(nn_connect(_nanoSock, uri.toStringz), file, line);
        _uri = uri;
        _connection = Connection.connected;
    }

    /// bind
    void bind(in string uri, in string file = __FILE__, in size_t line = __LINE__) {
        import std.string: toStringz;
        enforceNanoMsgRet(nn_bind(_nanoSock, uri.toStringz), file, line);
        _uri = uri;
        _connection = Connection.bound;
    }

    /// get protocol
    Protocol protocol() @safe @nogc pure const nothrow {
        return _protocol;
    }

    /// get URI
    string uri() @safe @nogc pure const nothrow {
        return _uri;
    }

    /// toString
    string toString() @safe pure const {
        import std.conv: text;

        if(_connection == Connection.none)
            return text(protocol);

        const connText = _connection == Connection.bound ? "@" : "@@";
        return text(_protocol, connText, _uri);
    }

private:

    enum Connection {
        none,
        bound,
        connected,
    }

    int _nanoSock = INVALID_FD;
    Protocol _protocol;
    string _uri;
    Connection _connection;

    void enforceNanoMsgRet(E)(lazy E expr, string file = __FILE__, size_t line = __LINE__) const {
        import std.conv: text;
        const value = expr();
        if(value < 0)
            throw new Exception(text("nanomsg expression failed with value ", value,
                                     " errno ", nn_errno, ", error: ", nn_strerror(nn_errno)),
                                file,
                                line);
    }

    // the int level and option values needed by the nanomsg C API
    static struct OptionC {
        int level;
        int option;
    }

    static OptionC toOptionC(Option option) @safe {
        final switch(option) with(Option) {
            case lingerMs:
                return OptionC(NN_SOL_SOCKET, NN_LINGER);

            case sendBufferSize:
                return OptionC(NN_SOL_SOCKET, NN_SNDBUF);

            case receiveBufferSize:
                return OptionC(NN_SOL_SOCKET, NN_RCVBUF);

            case receiveMaxSize:
                return OptionC(NN_SOL_SOCKET, NN_RCVMAXSIZE);

            case sendTimeoutMs:
                return OptionC(NN_SOL_SOCKET, NN_SNDTIMEO);

            case receiveTimeoutMs:
                return OptionC(NN_SOL_SOCKET, NN_RCVTIMEO);

            case reconnectIntervalMs:
                return OptionC(NN_SOL_SOCKET, NN_RECONNECT_IVL);

            case reconnectIntervalMax:
                return OptionC(NN_SOL_SOCKET, NN_RECONNECT_IVL_MAX);

            case sendPriority:
                return OptionC(NN_SOL_SOCKET, NN_SNDPRIO);

            case receivePriority:
                return OptionC(NN_SOL_SOCKET, NN_RCVPRIO);

            case ipv4Only:
                return OptionC(NN_SOL_SOCKET, NN_IPV4ONLY);

            case socketName:
                return OptionC(NN_SOL_SOCKET, NN_SOCKET_NAME);

            case timeToLive:
                return OptionC(NN_SOL_SOCKET, NN_TTL);

            case subscribeTopic:
                return OptionC(NN_SUB, NN_SUB_SUBSCRIBE);

            case unsubscribeTopic:
                return OptionC(NN_SUB, NN_SUB_UNSUBSCRIBE);

            case tcpNoDelay:
                return OptionC(NN_TCP, NN_TCP_NODELAY);

            case surveyorDeadlineMs:
                return OptionC(NN_SURVEYOR, NN_SURVEYOR_DEADLINE);
        }
    }

    void setOption(T)(int level, int option, ref T val) const if(isArray!T) {
        enforceNanoMsgRet(nn_setsockopt(_nanoSock, level, option, val.ptr, val.length));
    }

    void setOption(T)(int level, int option, T val) const if(!isArray!T) {
        enforceNanoMsgRet(nn_setsockopt(_nanoSock, level, option, &val, val.sizeof));
    }

    T getOption(T)(int level, int option) const if(isArray!T) {
        import std.traits: Unqual;
        import std.conv: to;

        // ElementType!string is dchar, and we don't want that,
        // so instead we use this typeof
        alias U = Unqual!(typeof(T.init[0]))[1000];
        U val;
        ulong length = val.length;
        enforceNanoMsgRet(nn_getsockopt(_nanoSock, level, option, cast(void*)val.ptr, &length));
        return val[0 .. length].to!T;
    }

    T getOption(T)(int level, int option) const if(!isArray!T) {
        import std.exception: enforce;
        import std.conv: text;

        T val;
        ulong length = T.sizeof;
        enforceNanoMsgRet(nn_getsockopt(_nanoSock, level, option, &val, &length));
        enforce(length == T.sizeof,
                text("getsockopt returned ", length, " but sizeof(", T.stringof, ") is ", T.sizeof));
        return val;
    }

    static int flags(Flag!"blocking" blocking) @safe pure {
        return blocking ? 0 : NN_DONTWAIT;
    }
}

/// check nanomsg socket
void checkNanoSocket(T)() {
    T s = T(NanoSocket.Protocol.subscribe, ConnectTo("foobar"));
    s.send("foobar");
    s.setOption(NanoSocket.Option.subscribeTopic, "topic");
    s.setOption(NanoSocket.Option.receiveTimeoutMs, 100);
    ubyte[] msg = s.receive(Yes.blocking);
    s.send(msg);
}
enum isNanoSocket(T) = is(typeof(checkNanoSocket!T));
static assert(isNanoSocket!NanoSocket);

/**
        Examples:
*/
/// set/get option
///
@("set/get option")
unittest {
    auto sock = NanoSocket(NanoSocket.Protocol.subscribe);
    sock.getOption!int(NanoSocket.Option.sendTimeoutMs).shouldEqual(-1);
    sock.setOption(NanoSocket.Option.sendTimeoutMs, 42);
    sock.getOption!int(NanoSocket.Option.sendTimeoutMs).shouldEqual(42);
}

/// publish/subscribe
///
@("pub/sub")
unittest {
    const uri = "inproc://test_pubsub";
    auto pub = NanoSocket(NanoSocket.Protocol.publish, BindTo(uri));
    auto sub = NanoSocket(NanoSocket.Protocol.subscribe, ConnectTo(uri));
    sub.setOption(NanoSocket.Option.subscribeTopic, "foo");

    // messages that start with the subscription topic should be received
    pub.send("foo/hello");
    sub.receive(No.blocking).shouldEqual("foo/hello");

    // but not messages that don't
    pub.send("bar/oops");
    sub.receive(No.blocking).shouldBeEmpty;

    // after unsubscribing, messages are no longer received
    sub.setOption(NanoSocket.Option.unsubscribeTopic, "foo");
    pub.send("foo/hello");
    sub.receive(No.blocking).shouldBeEmpty;
}

/// request/response
///
@("req/rep")
unittest {
    import std.concurrency: spawnLinked, send;

    const uri = "inproc://test_reqrep";
    const requester = NanoSocket(NanoSocket.Protocol.request, ConnectTo(uri));

    enum timeoutMs = 50;
    requester.setOption(NanoSocket.Option.receiveTimeoutMs, timeoutMs);

    auto tid = spawnLinked(&responder, uri, timeoutMs);
    requester.send("shake?").shouldEqual("shake? yep!");
    tid.send(Stop());
}

/**
    Example:
        utility function
*/
version(unittest) {
    import std.concurrency: Tid;

    /// utility struct for unit test
    struct Respond { string value; }
    /// utility struct for unit test
    struct Stop {}

    /// utility function for unit tests/examples
    void responder(in string uri, in int timeoutMs) {
        import std.concurrency: receiveTimeout;
        import std.datetime: msecs;

        const socket = NanoSocket(NanoSocket.Protocol.response, BindTo(uri));
        socket.setOption(NanoSocket.Option.receiveTimeoutMs, timeoutMs);

        for(bool done; !done;) {
            receiveTimeout(10.msecs,
                (Stop _) {
                    done = true;
                },
            );

            const bytes = socket.receive(No.blocking);
            if(bytes.length) socket.send(bytes ~ cast(ubyte[])" yep!");
        }
    }
}

/**
    Example:
        push/pull over TCP
*/
@("push/pull over TCP")
unittest {
    import core.thread: Thread, msecs;

    auto pull = NanoSocket(NanoSocket.Protocol.pull, BindTo("tcp://localhost:13248"));
    auto push = NanoSocket(NanoSocket.Protocol.push, ConnectTo("tcp://localhost:13248"));

    enum numTimes = 10;

    foreach(i; 0 .. numTimes)
        push.send("foo");

    Thread.sleep(50.msecs);

    foreach(i; 0 .. numTimes)
        pull.receive(No.blocking).shouldEqual("foo");
}

/**
    Example:
        push/pull over IPC
*/
@HiddenTest /// it's here to show that this can fail, but it doesn't always
@("push/pull over IPC")
unittest {
    auto pull = NanoSocket(NanoSocket.Protocol.pull, BindTo("ipc://nanomsg_ipc_push_pull_test"));
    auto push = NanoSocket(NanoSocket.Protocol.push, ConnectTo("ipc://nanomsg_ipc_push_pull_test"));

    enum numTimes = 5;

    foreach(i; 0 .. numTimes)
        push.send("foo");

    foreach(i; 0 .. numTimes)
        pull.receive(No.blocking).shouldEqual("foo");
}
