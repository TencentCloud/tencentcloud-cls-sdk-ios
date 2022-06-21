
#import <UIKit/UIKit.h>
#import <TencentCloudLogProducer.h>
#import "PrefixHeader.pch"
#import "UtilInfo.h"

@interface ViewController : UIViewController

- (UIButton *) createButton: (NSString *) title andAction: (SEL) action andX: (CGFloat) x andY: (CGFloat) y;

- (UIButton *) createButton: (NSString *) title andAction: (SEL) action andX: (CGFloat) x andY: (CGFloat) y andWidth: (CGFloat) width andHeight: (CGFloat) height;

- (UILabel *) createLabel: (NSString *)title andX: (CGFloat) x andY: (CGFloat) y;

- (UILabel *) createLabel: (NSString *) title andX: (CGFloat) x andY: (CGFloat) y andWidth: (CGFloat) width andHeight: (CGFloat) height;

- (UITextView *) createTextView: (NSString *) text andX: (CGFloat) x andY: (CGFloat) y andWidth: (CGFloat) width andHeight: (CGFloat) height;

@end

