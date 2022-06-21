
#import "AppDelegate.h"
#import "UtilInfo.h"
#import "MainViewController.h"

#import <TencentCloudLogProducer.h>
@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window=[[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    MainViewController *viewController = [[MainViewController alloc] init];
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
    [navigationController.navigationBar setBarTintColor:[UIColor greenColor]];
    navigationController.view.tintColor = [UIColor greenColor];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];


    DemoUtils *utils = [DemoUtils sharedInstance];
    [utils setEndpoint:@"ap-guangzhou.cls.tencentcs.com"];
    [utils setAccessKeyId:@""];
    [utils setAccessKeySecret:@""];
    [utils setTopic:@""];
    
    CLSLogV(@"endpoint: %@", [utils endpoint]);
    CLSLogV(@"accessKeyId: %@", [utils accessKeyId]);
    CLSLogV(@"accessKeySecret: %@", [utils accessKeySecret]);
    CLSLogV(@"topic: %@", [utils topic]);
    return YES;
}


@end

