# CombineGRPC

> gRPC and Combine, better together.

CombineGRPC is a library that provides [Combine framework](https://developer.apple.com/documentation/combine) integration for [gRPC Swift](https://github.com/grpc/grpc-swift). It provides two flavours of functions, `call` and `handle`. Use `call` to make gRPC calls on the client side, and `handle` to handle incoming RPC calls on the server side. CombineGRPC provides versions of `call` and `handle` for all RPC styles. Here are the input and output types for each.

--- | ---
| Unary | `Request -> AnyPublisher<Response, GRPCStatus>` |
| Server streaming | `Request -> AnyPublisher<Response, GRPCStatus>` |
| Client streaming | `AnyPublisher<Request, Error> -> AnyPublisher<Response, GRPCStatus>` |
| Bidirectional streaming | `AnyPublisher<Request, Error> -> AnyPublisher<Response, GRPCStatus>` |

When you make a unary call, you provide a request message, and get back a response publisher. The response publisher will either publish a single response, or fail with a `GRPCStatus` error. Similarly, if you are handling a unary RPC call, you provide a handler that takes a request parameter and returns an `AnyPublisher<Response, GRPCStatus>`.

You can follow the same intuition to understand the types for the other RPC styles. The only difference is that publishers for the streaming RPCs may publish zero or more messages instead of the single response message that is expected from the unary response publisher.

## Quick Tour

Let's see a quick example. Consider the following protobuf definition for a simple echo service. The service defines one bidirectional RPC. You send it a stream of messages and it echoes the messages back to you.

```protobuf
syntax = "proto3";

service EchoService {
  rpc SayItBack (stream EchoRequest) returns (stream EchoResponse);
}

message EchoRequest {
  string message = 1;
}

message EchoResponse {
  string message = 1;
}
```

To implement the server, you provide a handler function that takes an input stream `AnyPublisher<EchoRequest, Error>` and returns an output stream `AnyPublisher<EchoResponse, GRPCStatus>`.

```swift
class EchoServiceProvider: EchoProvider {
  
  // Simple bidirectional RPC that echoes back each request message
  func sayItBack(context: StreamingResponseCallContext<EchoResponse>) -> EventLoopFuture<(StreamEvent<EchoRequest>) -> Void> {
    handle(context) { requests in
      requests
        .map { req in
          EchoResponse.with { $0.message = req.message }
        }
        .mapError { _ in .processingError }
        .eraseToAnyPublisher()
    }
  }
}
```

On the client side, set up the gRPC client as you would using [swift-grpc](https://github.com/grpc/grpc-swift). For example:

```swift
let configuration = ClientConnection.Configuration(
  target: ConnectionTarget.hostAndPort("localhost", 8080),
  eventLoopGroup: GRPCNIO.makeEventLoopGroup(loopCount: 1)
)
let echoClient = EchoServiceClient(connection: ClientConnection(configuration: configuration))
```

To call the service, use `call`. You provide it with a stream of requests `AnyPublisher<EchoRequest, Error>` and you get back a stream `AnyPublisher<EchoResponse, GRPCStatus>` of responses from the server.

```swift
let requests = repeatElement(EchoRequest.with { $0.message = "hello"}, count: 10)
let requestStream: AnyPublisher<EchoRequest, Error> =
  Publishers.Sequence(sequence: requests).eraseToAnyPublisher()

call(echoClient.sayItBack)(requestStream)
  .filter { $0.message == "hello" }
  .count()
  .sink(receiveValue: { count in
    assert(count == 10)
  })
```

That's it! You have set up bidirectional streaming between a server and client. The method `sayItBack` of `EchoServiceClient` is generated by swift-grpc. Notice that `call` is curried. You can preconfigure RPC calls using partial application:

```swift
let sayItBack = call(echoClient.sayItBack)

sayItBack(requestStream).map { response in
  // ...
}
```

There is also a version of `call` that can partially apply `CallOptions`.

```swift
let options = CallOptions(timeout: try! .seconds(5))
let callWithTimeout: ConfiguredBidirectionalStreamingRPC<EchoRequest, EchoResponse> = call(options)

callWithTimeout(echoClient.sayItBack)(requestStream).map { response in
  // ...
}
```

It's handy for configuring authenticated calls.

```swift
let authenticatedCall = call(CallOptions(customMetadata: authenticationHeaders))

authenticatedCall(userClient.getProfile)(getProfileRequest).map { profile in
  // ...
}
```

## Quick Start

### Generating Swift Code from Protobuf

Install the [protoc](https://github.com/protocolbuffers/protobuf) Protocol Buffer compiler and the [swift-protobuf](https://github.com/apple/swift-protobuf) plugin.

```text
brew install protobuf
brew install swift-protobuf
```

Next, download the latest version of grpc-swift with NIO support. Currently that means [gRPC Swift 1.0.0-alpha.1](https://github.com/grpc/grpc-swift/releases/tag/1.0.0-alpha.1). Unarchive the downloaded file and build the swift-grpc plugin by running make in the root directory of the project.

```text
make plugin
```

Put the built binary somewhere in your $PATH. Now you are ready to generate Swift code from protobuf interface definition files.

Let's generate the message types, gRPC server and gRPC client for Swift.

```text
protoc hot_and_cold.proto --swift_out=Generated/
protoc hot_and_cold.proto --swiftgrpc_out=Generated/
```

You'll see that protoc has created two source files for us.

```text
ls Generated/
hot_and_cold.grpc.swift
hot_and_cold.pb.swift
```

### Adding CombineGRPC to Your Project

For Swift Package Manager, add CombineGRPC as a dependency to your Package.swift configuration file.

```swift
dependencies: [
  .package(url: "https://github.com/vyshane/grpc-swift-combine.git", from: "0.1.0"),
],
```

### Making gRPC Calls

CombineGRPC provides `call()` functions to make client calls. All the different types of RPC calls are supported.

#### Unary Call

A unary call takes the request message as a parameter and returns a stream of one response. The response stream may fail with a `GRPCStatus` error.

```swift
call(UnaryRPC)(Request) -> AnyPublisher<Response, GRPCStatus>
```

For example, given the following protobuf:

```protobuf
service UserService {
  GetProfile (GetProfileRequest) returns (Profile);
  // ...
}

message GetProfileRequest {
  string username = 1;
  string team = 2;
}

message Profile {
  string first_name = 1;
  string last_name = 2;
  bool isContributor = 3;
  // ...
}
```

We can make a unary RPC call to the service like this:

```swift
let request = GetProfileRequest.with {
  $0.username = "shane"
  $0.team = "node.mu"
}

call(userClient.getProfile)(request)
  .map { profile in
    return profile.isContributor
  }
  .assign(to: \.isEnabled, on: mergeButton)
```

#### Server Streaming Call

A server streaming call takes the request message as a parameter and returns a stream of responses. The response stream may fail with a `GRPCStatus` error.

```swift
call(ServerStreamingRPC)(Request) -> AnyPublisher<Response, GRPCStatus>
```

Example:

```swift
let nearbyPlaces = call(pointsOfInterestClient.nearbyPlaces)

let coordinate = Coordinate.with {
  $0.lat = -20.26381
  $0.lon = 57.4791
}

nearbyPlaces(coordinate)
  .filter { $0.type == .restaurant }
  .count()
  .assign(to: \.text, on: foodAndBeveragesLabel)
```

#### Client Streaming Call

A client streaming call takes a stream of requests as a parameter and returns a response stream of one message. The response stream may fail with a `GRPCStatus` error.

```swift
call(ClientStreamingRPC)(AnyPublisher<Request, Never>) -> AnyPublisher<Response, GRPCStatus>
```

#### Bidirectional Streaming Call

A bidirectional streaming call takes a stream of requests as a parameter and returns a stream of responses. The response stream may fail with a `GRPCStatus` error.

```swift
call(BidirectionalRPC)(AnyPublisher<Request, Never>) -> AnyPublisher<Response, GRPCStatus>
```

#### Configuring RPC Calls

```swift
// TODO
// Partial application of CallOptions
```

### Implementing RPC Handlers for the Server

The [Server Implementation Tests](Tests/CombineGRPCTests/Server%20Implementations) are good examples of how to use the RPC handlers on the server side. You can find the matching protobuf [here](Tests/Protobuf/test_scenarios.proto).

#### Unary Handler

```swift
// TODO
```

#### Server Streaming Handler

```swift
// TODO
```

#### Client Streaming Handler

```swift
// TODO
```

#### Bidirectional Streaming Handler

```swift
// TODO
```

## Compatibility

Since this library integrates with Combine, it only works on platforms that support Combine. This currently means the following minimum versions: macOS 10.15 Catalina, iOS 13, watchOS 6 and tvOS 13.

## Status

This project is a work in progress and should be considered experimental.

RPC Client Calls

- [x] Unary
- [x] Client streaming
- [x] Server streaming
- [x] Bidirectional streaming

Server Side Handlers

- [x] Unary
- [x] Client streaming
- [x] Server streaming
- [x] Bidirectional streaming

End-to-end Tests

- [x] Unary
- [ ] Client streaming (Done, pending upstream [grpc-swift #520](https://github.com/grpc/grpc-swift/issues/520))
- [x] Server streaming
- [ ] Bidirectional streaming (Done, pending upstream [grpc-swift #520](https://github.com/grpc/grpc-swift/issues/520))
- [ ] Stress tests

Documentation

- [ ] Inline documentation using Markdown in comments
- [ ] Unary
- [ ] Client streaming
- [ ] Server streaming
- [ ] Bidirectional streaming
- [ ] Sample project

Maybe

- [ ] Automatic client call retries, e.g. to support ID token refresh on expire
