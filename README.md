# CombineGRPC

> gRPC and Combine, better together.

CombineGRPC is a library that provides [Combine framework](https://developer.apple.com/documentation/combine) integration for [gRPC Swift](https://github.com/grpc/grpc-swift).

Protobuf

```protobuf
syntax = "proto3";

service HotAndCold {
  rpc AskOnce(AmIClose) returns (Answer);
  rpc KeepAsking(stream AmIClose) returns (stream Answer);
}

message AmIClose {
  double latitude = 1;
  double longitude = 2;
}

message Answer {
  Temperature temperature = 1;
}

enum Temperature {
  TEMPERATURE_UNSPECIFIED = 0;
  COLD = 1;
  COOL = 2;
  NEUTRAL = 3;
  WARM = 4;
  HOT = 5;
}
```

Swift

```swift
call(client.askOnce)(AmIClose) -> AnyPublisher<Answer, GRPCStatus>
call(client.keepAsking)(AnyPublisher<AmIClose, Never>) -> AnyPublisher<Answer, GRPCStatus>
```

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

- [ ] Unary
- [ ] Client streaming
- [ ] Server streaming
- [ ] Bidirectional streaming

Maybe

- [ ] Automatic client call retries, e.g. to support ID token refresh on expire
