//#import <XCTest/XCTest.h>
//#import "CLSHttpingV2.h"
//#import "CLSResponse.h"
//#import "CLSNetworkUtils.h"
//
//// 测试回调类型
//typedef void(^CompleteCallback)(CLSResponse *result);
//
//@interface CLSHttpingV2Tests : XCTestCase
//@property (nonatomic, strong) CLSHttpRequest *baseRequest; // 基础请求配置
//@end
//
//@implementation CLSHttpingV2Tests
//
//- (void)setUp {
//    [super setUp];
//    // 初始化基础请求（使用腾讯云CLS的ping接口，确保返回规范）
//    self.baseRequest = [[CLSHttpRequest alloc] init];
//    self.baseRequest.domain = @"https://sa-saopaulo.cls.tencentcs.com/ping"; // 标准测试域名
//    self.baseRequest.topicId = @"test_topic_123"; // 非空topicId
//    self.baseRequest.timeout = 15; // 超时时间15秒
//    self.baseRequest.enableSSLVerification = YES;
//    self.baseRequest.enableMultiplePortsDetect = NO; // 单网卡测试
//    self.baseRequest.detectEx = @{@"key1": @"value1"}; // 自定义扩展字段
//    self.baseRequest.userEx = @{@"key2": @"valuoe2"};
//}
//
//- (void)tearDown {
//    [super tearDown];
//    self.baseRequest = nil;
//}
//
//#pragma mark - 核心功能测试：正常HTTPing响应完整性
//
///// 验证正常响应的JSON结构和所有必填字段
//- (void)testHttpingNormalResponse {
//    XCTestExpectation *expectation = [self expectationWithDescription:@"正常HTTPing响应验证"];
//    
//    [CLSMultiInterfaceHttping start:self.baseRequest complate:^(CLSResponse *result) {
//        // 1. 验证响应基础有效性
//        XCTAssertNotNil(result, "响应对象不能为空");
//        XCTAssertNotNil(result.content, "content字段不能为空（JSON字符串）");
//        
//        // 2. 将content反序列化为字典，验证JSON格式正确性
//        NSData *jsonData = [result.content dataUsingEncoding:NSUTF8StringEncoding];
//        NSDictionary *reportData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
//        XCTAssertNotNil(reportData, "content不是有效的JSON格式");
//        
//        // 3. 验证核心字段存在性和类型
//        NSArray *requiredFields = @[
//            @"tcpTime", @"src", @"trace_id", @"url", @"host_ip", @"httpCode",
//            @"waitDnsTime", @"receiveBytes", @"ts", @"dnsTime", @"method",
//            @"remoteAddr", @"domain", @"firstByteTime", @"timestamp",
//            @"allByteTime", @"bandwidth", @"requestTime", @"startDate"
//        ];
//        for (NSString *field in requiredFields) {
//            XCTAssertNotNil(reportData[field], "缺失必填字段：%@", field);
//        }
//        
//        // 4. 验证字段值合法性
//        XCTAssertEqualObjects(reportData[@"src"], @"app", @"src字段值错误");
//        XCTAssertEqualObjects(reportData[@"method"], @"http", @"method字段值错误");
//        XCTAssertEqual([reportData[@"httpCode"] integerValue], 200, @"HTTP状态码应为200");
//        XCTAssertEqualObjects(reportData[@"domain"], @"sa-saopaulo.cls.tencentcs.com", @"domain解析错误");
//        XCTAssertGreaterThan([reportData[@"tcpTime"] doubleValue], 0, @"tcpTime应大于0");
//        XCTAssertGreaterThan([reportData[@"requestTime"] doubleValue], 0, @"requestTime应大于0");
//        
//        // 5. 验证嵌套字段（netInfo、desc、headers等）
//        XCTAssertNotNil(reportData[@"netInfo"], @"netInfo字段缺失");
//        XCTAssertNotNil(reportData[@"netInfo"][@"usedNet"], @"netInfo.usedNet缺失");
//        XCTAssertNotNil(reportData[@"desc"], @"desc字段缺失");
//        XCTAssertNotNil(reportData[@"desc"][@"callStart"], @"desc.callStart缺失");
//        XCTAssertNotNil(reportData[@"headers"], @"headers字段缺失");
//        XCTAssertNotNil(reportData[@"headers"][@"date"], @"headers.date缺失");
//        
//        // 6. 验证自定义扩展字段
//        XCTAssertEqualObjects(reportData[@"detectEx"][@"key1"], @"value1", @"detectEx字段不匹配");
//        XCTAssertEqualObjects(reportData[@"userEx"][@"key2"], @"valuoe2", @"userEx字段不匹配");
//        
//        [expectation fulfill];
//    }];
//    
//    [self waitForExpectationsWithTimeout:20 handler:^(NSError *error) {
//        if (error) {
//            XCTFail("测试超时：%@", error.localizedDescription);
//        }
//    }];
//}
//
//#pragma mark - 边界条件测试：字段格式与范围
//
///// 验证时间相关字段的格式和逻辑（如ts与timestamp应接近）
//- (void)testTimeFieldsConsistency {
//    XCTestExpectation *expectation = [self expectationWithDescription:@"时间字段一致性验证"];
//    
//    [CLSMultiInterfaceHttping start:self.baseRequest complate:^(CLSResponse *result) {
//        NSData *jsonData = [result.content dataUsingEncoding:NSUTF8StringEncoding];
//        NSDictionary *reportData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
//        
//        // 验证时间戳格式（应为毫秒级时间戳，数值类型）
//        XCTAssertTrue([reportData[@"ts"] isKindOfClass:[NSNumber class]], @"ts应为数字类型");
//        XCTAssertTrue([reportData[@"timestamp"] isKindOfClass:[NSNumber class]], @"timestamp应为数字类型");
//        
//        // 验证ts与timestamp应接近（同一请求的时间戳差异应小于1秒）
//        NSTimeInterval ts = [reportData[@"ts"] doubleValue];
//        NSTimeInterval timestamp = [reportData[@"timestamp"] doubleValue];
//        XCTAssertLessThan(fabs(ts - timestamp), 1000, @"ts与timestamp差异过大");
//        
//        // 验证desc中的时间格式（应为"yyyy-MM-dd HH:mm:ss.SSS"）
//        NSString *callStartTime = reportData[@"desc"][@"callStart"];
//        NSRegularExpression *timeRegex = [NSRegularExpression regularExpressionWithPattern:@"\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\.\\d{3}" options:0 error:nil];
//        NSInteger matchCount = [timeRegex numberOfMatchesInString:callStartTime options:0 range:NSMakeRange(0, callStartTime.length)];
//        XCTAssertEqual(matchCount, 1, @"callStart时间格式错误：%@", callStartTime);
//        
//        [expectation fulfill];
//    }];
//    
//    [self waitForExpectationsWithTimeout:20 handler:nil];
//}
//
//#pragma mark - 异常场景测试：错误处理与JSON完整性
//
///// 测试参数缺失时的错误响应（确保JSON格式仍有效）
//- (void)testMissingParameters {
//    XCTestExpectation *expectation = [self expectationWithDescription:@"参数缺失错误响应"];
//    
//    // 构造缺失topicId的请求
//    CLSHttpRequest *invalidRequest = [[CLSHttpRequest alloc] init];
//    invalidRequest.domain = self.baseRequest.domain;
//    invalidRequest.topicId = nil; // 缺失必填参数
//    
//    [CLSMultiInterfaceHttping start:invalidRequest complate:^(CLSResponse *result) {
//        // 验证错误响应仍为有效JSON
//        NSData *jsonData = [result.content dataUsingEncoding:NSUTF8StringEncoding];
//        NSDictionary *errorData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
//        XCTAssertNotNil(errorData, "错误响应的content不是有效JSON");
//        XCTAssertEqualObjects(errorData[@"error"], @"lack param", @"错误信息不正确");
//        
//        [expectation fulfill];
//    }];
//    
//    [self waitForExpectationsWithTimeout:5 handler:nil];
//}
//
///// 测试超时场景的响应字段（确保错误场景下核心字段仍存在）
//- (void)testTimeoutResponse {
//    XCTestExpectation *expectation = [self expectationWithDescription:@"超时响应验证"];
//    
//    // 构造超时请求（无效端口）
//    CLSHttpRequest *timeoutRequest = [[CLSHttpRequest alloc] init];
//    timeoutRequest.domain = @"https://sa-saopaulo.cls.tencentcs.com:8081"; // 无效端口
//    timeoutRequest.topicId = self.baseRequest.topicId;
//    timeoutRequest.timeout = 2; // 短超时
//    
//    [CLSMultiInterfaceHttping start:timeoutRequest complate:^(CLSResponse *result) {
//        NSData *jsonData = [result.content dataUsingEncoding:NSUTF8StringEncoding];
//        NSDictionary *reportData = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
//        
//        // 验证错误信息和核心字段
//        XCTAssertNotNil(reportData[@"error"], @"超时响应未包含error字段");
//        XCTAssertEqualObjects(reportData[@"method"], @"http", @"错误场景下method仍应存在");
//        XCTAssertEqualObjects(reportData[@"url"], timeoutRequest.domain, @"url字段应保持一致");
//        
//        [expectation fulfill];
//    }];
//    
//    [self waitForExpectationsWithTimeout:5 handler:nil];
//}
//
//#pragma mark - 辅助测试：JSON序列化/反序列化兼容性
//
///// 验证CLSResponse的complateResultWithContent方法是否正确生成JSON
//- (void)testResponseJsonSerialization {
//    // 构造测试数据
//    NSDictionary *testData = @{
//        @"tcpTime": @123.45,
//        @"httpCode": @200,
//        @"netInfo": @{@"usedNet": @"wifi"},
//        @"desc": @{@"callStart": @"2025-12-11 00:00:00.000"}
//    };
//    
//    // 生成响应对象
//    CLSResponse *response = [CLSResponse complateResultWithContent:testData];
//    
//    // 验证JSON序列化正确性
//    XCTAssertNotNil(response.content, @"序列化失败，content为空");
//    NSData *jsonData = [response.content dataUsingEncoding:NSUTF8StringEncoding];
//    NSDictionary *deserialized = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
//    XCTAssertNotNil(deserialized, @"生成的JSON无法反序列化");
//    XCTAssertEqualObjects(deserialized[@"httpCode"], @200, @"序列化后字段值不匹配");
//    XCTAssertEqualObjects(deserialized[@"netInfo"][@"usedNet"], @"wifi", @"嵌套字段序列化失败");
//}
//
//@end
