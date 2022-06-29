
#import "MainViewController.h"
#import "ViewController.h"
#import "ProducerExampleController.h"
#import "ProducerExampleDestroyController.h"
#import "ProducerExampleNetDiaController.h"

@interface MainViewController ()

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.title = @"CLS iOS Demo";
    [self.navigationController.navigationBar setBackgroundColor:[UIColor systemGreenColor]];

    UIColor * color = [UIColor whiteColor];
    NSDictionary * dict = [NSDictionary dictionaryWithObject:color forKey:NSForegroundColorAttributeName];
    self.navigationController.navigationBar.titleTextAttributes = dict;
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"返回" style:UIBarButtonItemStylePlain target:nil action:nil];

    [self initViews];
}

- (void) initViews {
    self.view.backgroundColor = [UIColor whiteColor];
    [self createButton:@"基本配置" andAction:@selector(gotoGeneralPage) andX: 0 andY: 0];

    [self createButton:@"销毁配置" andAction:@selector(gotoDestroyPage) andX: SLCellWidth + SLPadding andY: 0];
    [self createButton:@"网络探测" andAction:@selector(gotoNetDiaPage) andX: (SLCellWidth + SLPadding) * 2 andY: 0];
    
}

- (void) gotoGeneralPage {
    [self gotoPageWithPage:[[ProducerExampleController alloc] init]];
}

- (void) gotoDestroyPage {
    [self gotoPageWithPage:[[ProducerExampleDestroyController alloc] init]];
}

- (void) gotoNetDiaPage {
    [self gotoPageWithPage:[[ProducerExampleNetDiaController alloc] init]];
}

- (void) gotoPageWithPage: (ViewController *) controller {
    [self.navigationController pushViewController:controller animated:YES];
}

@end

