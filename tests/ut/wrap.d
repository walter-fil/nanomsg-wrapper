module ut.wrap;


import nanomsg.wrap;
import unit_threaded;


@("send.try")
@safe unittest {
    import std.datetime: seconds, msecs;

    enum uri = "ipc://try_send_test";
    auto pull = NanoSocket(NanoSocket.Protocol.pull, BindTo(uri));
    auto push = NanoSocket(NanoSocket.Protocol.push, ConnectTo(uri));
    push.trySend("foo", TotalDuration(1.seconds), RetryDuration(10.msecs));
}


@("option")
@safe unittest {
    auto sock = NanoSocket(NanoSocket.Protocol.subscribe);
    sock.getOption!int(NanoSocket.Option.sendTimeoutMs).shouldEqual(-1);
    sock.setOption(NanoSocket.Option.sendTimeoutMs, 42);
    sock.getOption!int(NanoSocket.Option.sendTimeoutMs).shouldEqual(42);
}


@("pubsub")
@safe unittest {
    const uri = "inproc://test_pubsub";
    auto pub = NanoSocket(NanoSocket.Protocol.publish, const BindTo(uri));
    auto sub = NanoSocket(NanoSocket.Protocol.subscribe, ConnectTo(uri));
    sub.setOption(NanoSocket.Option.subscribeTopic, "foo");

    // messages that start with the subscription topic should be received
    pub.send("foo/hello");
    sub.receive(No.blocking).bytes.shouldEqual("foo/hello");

    // but not messages that don't
    pub.send("bar/oops");
    sub.receive(No.blocking).bytes.length.should == 0;

    // after unsubscribing, messages are no longer received
    sub.setOption(NanoSocket.Option.unsubscribeTopic, "foo");
    pub.send("foo/hello");
    sub.receive(No.blocking).bytes.length.should == 0;
}


// ASAN doesn't like D threads
version(nanomsg_wrapper_asan) {}
else {
    @("reqrep")
        @safe unittest {
        import std.concurrency: spawnLinked, send;

        const uri = "inproc://test_reqrep";
        const requester = NanoSocket(NanoSocket.Protocol.request, ConnectTo(uri));

        enum timeoutMs = 50;
        requester.setOption(NanoSocket.Option.receiveTimeoutMs, timeoutMs);

        auto tid = () @trusted { return spawnLinked(&responder, uri, timeoutMs); }();
        requester.send("shake?").bytes.shouldEqual("shake? yep!");
        () @trusted { tid.send(Stop()); }();
    }
}


private struct Respond { string value; }
private struct Stop {}

/// utility function for unit tests/examples
private void responder(in string uri, in int timeoutMs) {
    import std.concurrency: receiveTimeout;
    import std.datetime: msecs;

    const socket = NanoSocket(NanoSocket.Protocol.response, const BindTo(uri));
    socket.setOption(NanoSocket.Option.receiveTimeoutMs, timeoutMs);

    for(bool done; !done;) {
        receiveTimeout(10.msecs,
                       (Stop _) {
                           done = true;
                       },
            );

        const resp = socket.receive(No.blocking);
        if(resp.bytes.length) socket.send(resp.bytes ~ cast(ubyte[])" yep!");
    }
}


version(Windows) {} //FIXME
else {
    @("push.TCP")
    @safe unittest {
        import core.thread: Thread, msecs;

        auto pull = NanoSocket(NanoSocket.Protocol.pull, BindTo("tcp://localhost:13248"));
        auto push = NanoSocket(NanoSocket.Protocol.push, ConnectTo("tcp://localhost:13248"));

        enum numTimes = 10;

        foreach(i; 0 .. numTimes)
            push.send("foo");

        () @trusted { Thread.sleep(50.msecs); }();

        foreach(i; 0 .. numTimes)
            pull.receive(No.blocking).bytes.shouldEqual("foo");
    }
}


@HiddenTest /// it's here to show that this can fail, but it doesn't always
@("push.IPC")
@safe unittest {
    auto pull = NanoSocket(NanoSocket.Protocol.pull, BindTo("ipc://nanomsg_ipc_push_pull_test"));
    auto push = NanoSocket(NanoSocket.Protocol.push, ConnectTo("ipc://nanomsg_ipc_push_pull_test"));

    enum numTimes = 5;

    foreach(i; 0 .. numTimes)
        push.send("foo");

    foreach(i; 0 .. numTimes)
        pull.receive(No.blocking).bytes.shouldEqual("foo");
}


@("bind.several addresses at once")
@safe unittest {
    auto pull = NanoSocket(NanoSocket.Protocol.pull, BindTo(["ipc://nanomsg_ipc_push_pull_1",
                                                             "ipc://nanomsg_ipc_push_pull_2"]));
    pull.setOption(NanoSocket.Option.receiveTimeoutMs, 10);

    auto push1 = NanoSocket(NanoSocket.Protocol.push, ConnectTo("ipc://nanomsg_ipc_push_pull_1"));
    auto push2 = NanoSocket(NanoSocket.Protocol.push, ConnectTo("ipc://nanomsg_ipc_push_pull_2"));

    push1.setOption(NanoSocket.Option.sendTimeoutMs, 10);
    push2.setOption(NanoSocket.Option.sendTimeoutMs, 10);

    push1.send("foo");
    push2.send("bar");

    pull.receive.bytes.shouldEqual("foo");
    pull.receive.bytes.
        shouldEqual("bar");
}


@("init.after.construction")
@safe unittest {
    NanoSocket pull;
    NanoSocket push;

    pull.initialize(NanoSocket.Protocol.pull, BindTo("ipc://nanomsg_ipc_init_after"));
    push.initialize(NanoSocket.Protocol.push, ConnectTo("ipc://nanomsg_ipc_init_after"));

    pull.setOption(NanoSocket.Option.receiveTimeoutMs, 10);
    push.setOption(NanoSocket.Option.sendTimeoutMs, 10);

    push.send("foo");
    push.send("bar");

    pull.receive.bytes.shouldEqual("foo");
    pull.receive.bytes.shouldEqual("bar");
}


@("init.twice")
@safe unittest {
    NanoSocket pull;
    pull.initialize(NanoSocket.Protocol.pull, BindTo("ipc://nanomsg_ipc_init_twice"));
    pull.initialize(NanoSocket.Protocol.pull, BindTo("ipc://nanomsg_ipc_init_twice"));
}


@("init.send throws if not initialised")
@safe unittest {
    enum uri = "ipc://nanomsg_init_send_throws";
    auto pull = NanoSocket(NanoSocket.Protocol.pull, BindTo(uri));
    NanoSocket push;
    push.send("foo").shouldThrow;
}


@("receive.buffer.nothing")
@safe unittest {
    NanoSocket pull;
    pull.initialize(NanoSocket.Protocol.pull, BindTo("inproc://nanomsg_receive_buffer"));
    ubyte[1024] buf;
    scope bytes = pull.receive(buf, No.blocking);
    bytes.length.should == 0;
}


@("receive.buffer.something")
@safe unittest {

    import std.range: repeat, take;
    NanoSocket pull, push;

    enum uri = "inproc://nanomsg_big_receive";
    pull.initialize(NanoSocket.Protocol.pull, BindTo(uri));
    push.initialize(NanoSocket.Protocol.push, ConnectTo(uri));

    pull.setOption(NanoSocket.Option.receiveTimeoutMs, 10);
    push.setOption(NanoSocket.Option.sendTimeoutMs, 10);

    enum numBytes = 32_000;
    push.send(new ubyte[numBytes]);
    pull.receive.bytes.toBytes.shouldEqual(0.repeat.take(numBytes));
}


@("receive.nogc.explicit")
@safe unittest {
    enum uri = "inproc://nanomsg_receive_nogc";

    NanoSocket pull;
    pull.initialize(NanoSocket.Protocol.pull, BindTo(uri));
    pull.setOption(NanoSocket.Option.receiveTimeoutMs, 10);

    NanoSocket push;
    push.initialize(NanoSocket.Protocol.push, ConnectTo(uri));
    push.setOption(NanoSocket.Option.sendTimeoutMs, 10);

    push.send("Don't need the GC to receive");
    const buf = () @nogc { return pull.receiveNoGc; }();
    const str = () @trusted { return cast(const(char)[]) buf.bytes.dup; }();
    str.shouldEqual("Don't need the GC to receive");
}


@("receive.nogc.implicit")
@safe unittest {
    enum uri = "inproc://nanomsg_receive_nogc";

    NanoSocket pull;
    pull.initialize(NanoSocket.Protocol.pull, BindTo(uri));
    pull.setOption(NanoSocket.Option.receiveTimeoutMs, 10);

    NanoSocket push;
    push.initialize(NanoSocket.Protocol.push, ConnectTo(uri));
    push.setOption(NanoSocket.Option.sendTimeoutMs, 10);

    push.send("Don't need the GC to receive");
    const buf = pull.receive;
    const str = () @trusted { return cast(const(char)[]) buf.bytes.dup; }();
    str.shouldEqual("Don't need the GC to receive");
}


ubyte[] toBytes(T)(T bytes) @trusted {
    return cast(ubyte[]) bytes.dup;
}
