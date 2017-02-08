/**
 This module implements a D convenience API for nanomsg
 */

module nanomsg.wrap;

import nanomsg.bindings;
public import std.typecons: Yes, No;

version(unittest) import unit_threaded;

enum NanoProtocol {
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

enum NanoOption {
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

struct ConnectTo {
    string uri;
}

struct BindTo {
    string uri;
}

struct NanoSocket {

    import std.traits: isArray;
    import std.typecons: Flag;

    // or else sockets would be destroyed
    @disable this(this);

    enum INVALID_FD = -1;

    this(NanoProtocol protocol, int domain = AF_SP) @trusted {

        int protocolToInt(NanoProtocol protocol) {
            final switch(protocol) with(NanoProtocol) {
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
        enforceNanoMsgRet(_nanoSock);
    }

    this(in NanoProtocol protocol, in BindTo bindTo, int domain = AF_SP) @trusted {
        import std.string: replace;

        this(protocol, domain);

        // this is so it's easy to specify the same string
        // for both ends of the socket
        bind(bindTo.uri.replace("localhost", "*"));
    }

    this(in NanoProtocol protocol, in ConnectTo connectTo, int domain = AF_SP) @trusted {

        this(protocol, domain);
        connect(connectTo.uri);

        version(Windows) {
            // on Windows sometimes the socket tries to send before the TCP handshake
            import core.thread;
            Thread.sleep(100.msecs);
        }
    }

    ~this() @trusted {
        if(_nanoSock != INVALID_FD) {
            _nanoSock.nn_close;
        }
    }

    void setOption(T)(NanoOption option, T val) const {
        const optionC = toNanoOptionC(option);
        setOption(optionC.level, optionC.option, val);
    }

    T getOption(T)(NanoOption option) const {
        const optionC = toNanoOptionC(option);
        return getOption!T(optionC.level, optionC.option);
    }

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

    int send(T)(T[] data, Flag!"blocking" blocking = Yes.blocking) const {
        const int flags = blocking ? 0 : NN_DONTWAIT;
        return nn_send(_nanoSock, data.ptr, data.length, flags);
    }

    void connect(in string uri) @trusted const {
        import std.string: toStringz;
        enforceNanoMsgRet(nn_connect(_nanoSock, uri.toStringz));
    }

    void bind(in string uri) @trusted const {
        import std.string: toStringz;
        enforceNanoMsgRet(nn_bind(_nanoSock, uri.toStringz));
    }

private:

    int _nanoSock = INVALID_FD;

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
    static struct NanoOptionC {
        int level;
        int option;
    }

    static NanoOptionC toNanoOptionC(NanoOption option) @safe {
        final switch(option) with(NanoOption) {
            case lingerMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_LINGER);

            case sendBufferSize:
                return NanoOptionC(NN_SOL_SOCKET, NN_SNDBUF);

            case receiveBufferSize:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVBUF);

            case receiveMaxSize:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVMAXSIZE);

            case sendTimeoutMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_SNDTIMEO);

            case receiveTimeoutMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVTIMEO);

            case reconnectIntervalMs:
                return NanoOptionC(NN_SOL_SOCKET, NN_RECONNECT_IVL);

            case reconnectIntervalMax:
                return NanoOptionC(NN_SOL_SOCKET, NN_RECONNECT_IVL_MAX);

            case sendPriority:
                return NanoOptionC(NN_SOL_SOCKET, NN_SNDPRIO);

            case receivePriority:
                return NanoOptionC(NN_SOL_SOCKET, NN_RCVPRIO);

            case ipv4Only:
                return NanoOptionC(NN_SOL_SOCKET, NN_IPV4ONLY);

            case socketName:
                return NanoOptionC(NN_SOL_SOCKET, NN_SOCKET_NAME);

            case timeToLive:
                return NanoOptionC(NN_SOL_SOCKET, NN_TTL);

            case subscribeTopic:
                return NanoOptionC(NN_SUB, NN_SUB_SUBSCRIBE);

            case unsubscribeTopic:
                return NanoOptionC(NN_SUB, NN_SUB_UNSUBSCRIBE);

            case tcpNoDelay:
                return NanoOptionC(NN_TCP, NN_TCP_NODELAY);

            case surveyorDeadlineMs:
                return NanoOptionC(NN_SURVEYOR, NN_SURVEYOR_DEADLINE);
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
}

@("set/get option")
unittest {
    auto sock = NanoSocket(NanoProtocol.subscribe);
    sock.getOption!int(NanoOption.sendTimeoutMs).shouldEqual(-1);
    sock.setOption(NanoOption.sendTimeoutMs, 42);
    sock.getOption!int(NanoOption.sendTimeoutMs).shouldEqual(42);
}

@("pub/sub")
unittest {
    const uri = "inproc://test_pubsub";
    auto pub = NanoSocket(NanoProtocol.publish, BindTo(uri));
    auto sub = NanoSocket(NanoProtocol.subscribe, ConnectTo(uri));
    sub.setOption(NanoOption.subscribeTopic, "foo");

    // messages that start with the subscription topic should be received
    pub.send("foo/hello");
    sub.receive(No.blocking).shouldEqual("foo/hello");

    // but not messages that don't
    pub.send("bar/oops");
    sub.receive(No.blocking).shouldBeEmpty;

    // after unsubscribing, messages are no longer received
    sub.setOption(NanoOption.unsubscribeTopic, "foo");
    pub.send("foo/hello");
    sub.receive(No.blocking).shouldBeEmpty;
}


@("req/rep")
unittest {
    const uri = "inproc://test_reqrep";
    auto responder = NanoSocket(NanoProtocol.response, BindTo(uri));
    auto requester = NanoSocket(NanoProtocol.request, ConnectTo(uri));

    enum timeoutMs = 50;
    responder.setOption(NanoOption.receiveTimeoutMs, timeoutMs);
    requester.setOption(NanoOption.receiveTimeoutMs, timeoutMs);

    requester.send("shake?");
    responder.receive(Yes.blocking).shouldEqual("shake?");
    responder.send("yep!");
    requester.receive(Yes.blocking).shouldEqual("yep!");
}
