# Zig Chat Server
This is a basic chat server and client written in zig as a means of learning the language's features.
The server as well as all client instances are meant to be hosted on a single machine.
It features:
1. basic socket api interfacing
2. polling using the poll syscall
3. single threaded user input reading and message printing
4. up to 10 simultaneous connections allocated dynamically
The chat currently uses the socket file descriptor as a client identifier, username support is not yet implemented
## building
To build, simply run `zig build` inside of the `chat-server` as well as the `chat-client` directories (run zig build twice).
The corresponding executables will be located in the zig-out directory.
## usage
First, the server needs to be launched by running its executable (otherwise the clients will have nothing to connect to).
It listens by default on port 2028.
Then, each launched client will attempt to connect to the server, note that up to 10 concurrent connections are supported.
To write a message, type it in the process's terminal and press enter. It will be sent to the rest of the connected clients.
## future
There are multiple points that can be added once I feel like learning those mechanics of the language, such as:
1. testing
2. multi-threading (input thread and socket thread inside the client)
3. command line parsing for configuration options
