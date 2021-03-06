// Copyright 2019, Vy-Shane Xie
// Licensed under the Apache License, Version 2.0

import XCTest
import Combine
import GRPC
import NIO
@testable import CombineGRPC

@available(OSX 10.15, iOS 13, tvOS 13, *)
class ServerStreamingTests: XCTestCase {
  
  static var serverEventLoopGroup: EventLoopGroup?
  static var client: ServerStreamingScenariosClient?
  
  // Streams will be cancelled prematurely if cancellables are deinitialized
  static var retainedCancellables: Set<AnyCancellable> = []
  
  override class func setUp() {
    super.setUp()
    serverEventLoopGroup = try! makeTestServer(services: [ServerStreamingTestsService()])
    client = makeTestClient { channel, callOptions in
      ServerStreamingScenariosClient(channel: channel, defaultCallOptions: callOptions)
    }
  }
  
  override class func tearDown() {
    try! client?.channel.close().wait()
    try! serverEventLoopGroup?.syncShutdownGracefully()
    retainedCancellables.removeAll()
    super.tearDown()
  }
  
  func testOk() {
    let promise = expectation(description: "Call completes successfully")
    let client = ServerStreamingTests.client!
    let grpc = GRPCExecutor()

    grpc.call(client.ok)(EchoRequest.with { $0.message = "hello" })
      .filter { $0.message == "hello" }
      .count()
      .sink(
        receiveCompletion: { switch $0 {
          case .failure(let status):
            XCTFail("Unexpected status: " + status.localizedDescription)
          case .finished:
            promise.fulfill()
        }},
        receiveValue: { count in
          XCTAssert(count == 3)
        }
      )
      .store(in: &ServerStreamingTests.retainedCancellables)
    
    wait(for: [promise], timeout: 0.2)
  }
  
  func testFailedPrecondition() {
    let promise = expectation(description: "Call fails with failed precondition status")
    let failedPrecondition = ServerStreamingTests.client!.failedPrecondition
    let grpc = GRPCExecutor()
    
    grpc.call(failedPrecondition)(EchoRequest.with { $0.message = "hello" })
      .sink(
        receiveCompletion: { switch $0 {
          case .failure(let error):
            if error.status.code == .failedPrecondition {
              XCTAssert(error.trailingMetadata?.first(name: "custom") == "info")
              promise.fulfill()
            } else {
              XCTFail("Unexpected status: " + error.status.localizedDescription)
            }
          case .finished:
            XCTFail("Call should not succeed")
        }},
        receiveValue: { empty in
          XCTFail("Call should not return a response")
        }
      )
      .store(in: &ServerStreamingTests.retainedCancellables)
    
    wait(for: [promise], timeout: 0.2)
  }
  
  func testNoResponse() {
    let promise = expectation(description: "Call fails with deadline exceeded status")
    let client = ServerStreamingTests.client!
    let options = CallOptions(timeLimit: TimeLimit.timeout(.milliseconds(20)))
    let grpc = GRPCExecutor(callOptions: Just(options).eraseToAnyPublisher())
        
    grpc.call(client.noResponse)(EchoRequest.with { $0.message = "hello" })
      .sink(
        receiveCompletion: { switch $0 {
          case .failure(let error):
            if error.status.code == .deadlineExceeded {
              promise.fulfill()
            } else {
              XCTFail("Unexpected status: " + error.status.localizedDescription)
            }
          case .finished:
            XCTFail("Call should not succeed")
        }},
        receiveValue: { empty in
          XCTFail("Call should not return a response")
        }
      )
      .store(in: &ServerStreamingTests.retainedCancellables)
    
    wait(for: [promise], timeout: 0.2)
  }
  
  // TODO: Backpressure test
  
  
  static var allTests = [
    ("Server streaming OK", testOk),
    ("Server streaming failed precondition", testFailedPrecondition),
    ("Server streaming no response", testNoResponse),
  ]
}
