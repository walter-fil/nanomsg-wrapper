/**
    nanomsg is a socket library that provides several common communication patterns. It aims to make the networking layer fast, scalable, and easy to use.
    Implemented in C, it works on a wide range of operating systems with no further dependencies.
    
    This module implements D bindings and a convenience wrapper API for nanomsg

    Authors: Laeeth Isharc and Atila Neves (Kaleidic Associates Advisory Limited)

	Documentation:
		- http://nanomsg.code.kaleidic.io/nanomsg.html
        - http://nanomsg.code.kaleidic.io/nanomsg.wrap.responder.html
        - http://nanomsg.code.kaleidic.io/nanomsg.wrap.checkNanoSocket.html
        - http://nanomsg.code.kaleidic.io/examples/nanomsg.examples.html

 */
module nanomsg;

public import nanomsg.bindings;
public import nanomsg.wrap;
