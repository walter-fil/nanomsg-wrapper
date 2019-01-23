D Language wrapper and bindings for [nanomsg](http://nanomsg.org/documentation.html)
================================================================================================
* Ported to [Dlang](https://dlang.org) (2014,2015,2016,2017) by Laeeth Isharc.  Caveat emptor.
* Modified by Atila Neves

Simple example
--------------

```d

// server:
auto pullSock = NanoSocket(NanoSocket.Protocol.pull, BindTo("tcp://*:12345"));
auto bytes = pullSock.receive();

// client:
auto pushSock = NanoSocket(NanoSocket.Protocol.push, ConnectTo("tcp://localhost:12345));
pushSock.send([0, 1, 3, 4, 5]);

```

[Generated documentation](docs/nanomsg.html)
Low Level Examples [Docs](docs/examples/nanomsg.examples.html) [Code](examples)


@nogc
-----

There is an extra `NanoSocket` member function called `receiveNoGc` if the nogc dub package
is added as a dependency.
