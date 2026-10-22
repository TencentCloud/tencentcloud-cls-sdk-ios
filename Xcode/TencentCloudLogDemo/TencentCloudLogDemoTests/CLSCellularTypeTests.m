
#import <XCTest/XCTest.h>
#import <TencentCloudLogProducer/CLSNetworkUtils.h>

@interface CLSNetworkUtils (CLSTestExposed)
+ (NSString *)mapCellularInterfaceNameToType:(NSString *)cellularInterfaceName;
@end

@interface CLSCellularTypeTests : XCTestCase
@end

@implementation CLSCellularTypeTests

static NSArray<NSString *> *ClsAllowedCellularTypes(void) {
    return @[@"5G", @"4G", @"3G", @"cellular"];
}

static NSArray<NSString *> *ClsAllowedInterfaceTypes(void) {
    return @[@"wifi", @"5G", @"4G", @"3G", @"cellular"];
}

#pragma mark - mapCellularInterfaceNameToType:

- (void)testMap_NilInput_ReturnsNonNilCellular {
    NSString *type = [CLSNetworkUtils mapCellularInterfaceNameToType:nil];
    XCTAssertNotNil(type);
    NSArray *allowed = ClsAllowedCellularTypes();
    XCTAssertTrue([allowed containsObject:type], @"expect in {5G,4G,3G,cellular}, actual=%@", type);
}

- (void)testMap_EmptyStringInput_ReturnsNonNilCellular {
    NSString *type = [CLSNetworkUtils mapCellularInterfaceNameToType:@""];
    XCTAssertNotNil(type);
    NSArray *allowed = ClsAllowedCellularTypes();
    XCTAssertTrue([allowed containsObject:type]);
}

- (void)testMap_FakeCellularInterfaceName_ReturnsNonNil {
    NSString *type = [CLSNetworkUtils mapCellularInterfaceNameToType:@"pdp_ip99"];
    XCTAssertNotNil(type);
    NSArray *allowed = ClsAllowedCellularTypes();
    XCTAssertTrue([allowed containsObject:type], @"fake cellular ifname should degrade to cellular, actual=%@", type);
}

- (void)testMap_WifiInterfaceName_StillReturnsNonNil {
    NSString *type = [CLSNetworkUtils mapCellularInterfaceNameToType:@"en0"];
    XCTAssertNotNil(type);
    NSArray *allowed = ClsAllowedCellularTypes();
    XCTAssertTrue([allowed containsObject:type]);
}

#pragma mark - getAllNetworkInterfacesDetail

- (void)testGetAllInterfaces_DoesNotCrash {
    NSArray<NSDictionary *> *interfaces = nil;
    XCTAssertNoThrow(interfaces = [CLSNetworkUtils getAllNetworkInterfacesDetail]);
    XCTAssertNotNil(interfaces);
}

- (void)testGetAllInterfaces_EachEntryHasNonNilType {
    NSArray<NSDictionary *> *interfaces = [CLSNetworkUtils getAllNetworkInterfacesDetail];
    for (NSDictionary *iface in interfaces) {
        XCTAssertNotNil(iface[@"type"], @"iface %@ type should not be nil", iface[@"name"]);
        XCTAssertNotNil(iface[@"name"]);
        XCTAssertNotNil(iface[@"ip"]);
    }
}

- (void)testGetAllInterfaces_TypeValuesAreInAllowedSet {
    NSArray<NSDictionary *> *interfaces = [CLSNetworkUtils getAllNetworkInterfacesDetail];
    NSArray *allowed = ClsAllowedInterfaceTypes();
    for (NSDictionary *iface in interfaces) {
        NSString *type = iface[@"type"];
        XCTAssertTrue([allowed containsObject:type],
                      @"iface %@ type=%@ not in allowed set", iface[@"name"], type);
    }
}

- (void)testGetAllInterfaces_WiFiInterfacesClassifiedAsWifi {
    NSArray<NSDictionary *> *interfaces = [CLSNetworkUtils getAllNetworkInterfacesDetail];
    for (NSDictionary *iface in interfaces) {
        NSString *name = iface[@"name"];
        if ([name hasPrefix:@"en"]) {
            XCTAssertEqualObjects(iface[@"type"], @"wifi",
                                  @"en* iface should be classified as wifi, but %@ got %@", name, iface[@"type"]);
        }
    }
}

@end
