// GlassSearch - search pill ala iOS 26 untuk iOS 15 (SpringBoard)
// Pill liquid glass di atas dock -> tap -> blur + search bar nempel di atas keyboard.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface UIImage (GSPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end

#pragma mark - Glass views

@interface GSGradientView : UIView
@end
@implementation GSGradientView
+ (Class)layerClass { return [CAGradientLayer class]; }
@end

// Blur + sheen (kilau) + border tipis = pendekatan liquid glass di iOS 15
@interface GSGlassView : UIView
@property (nonatomic, readonly) UIView *content;
@end
@implementation GSGlassView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderWidth = 0.8;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;

    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = self.bounds;
    blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:blur];

    GSGradientView *sheen = [[GSGradientView alloc] initWithFrame:self.bounds];
    sheen.userInteractionEnabled = NO;
    sheen.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CAGradientLayer *gl = (CAGradientLayer *)sheen.layer;
    gl.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.28].CGColor,
                  (id)[UIColor colorWithWhite:1 alpha:0.05].CGColor,
                  (id)[UIColor colorWithWhite:1 alpha:0.00].CGColor,
                  (id)[UIColor colorWithWhite:1 alpha:0.12].CGColor];
    gl.locations = @[@0, @0.35, @0.7, @1];
    gl.startPoint = CGPointMake(0.1, 0);
    gl.endPoint = CGPointMake(0.9, 1);
    [self addSubview:sheen];

    _content = [[UIView alloc] initWithFrame:self.bounds];
    _content.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_content];
    return self;
}
@end

static UIImage *GSSymbol(NSString *name, CGFloat size) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:name withConfiguration:cfg];
}

// Search bar bawah: ikon kaca pembesar + text field + mic
@interface GSBar : GSGlassView
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIImageView *mic;
@end
@implementation GSBar
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _icon = [[UIImageView alloc] initWithImage:GSSymbol(@"magnifyingglass", 16)];
    _icon.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
    _icon.contentMode = UIViewContentModeCenter;
    _mic = [[UIImageView alloc] initWithImage:GSSymbol(@"mic.fill", 16)];
    _mic.tintColor = [UIColor colorWithWhite:1 alpha:0.6];
    _mic.contentMode = UIViewContentModeCenter;
    _field = [[UITextField alloc] init];
    _field.textColor = UIColor.whiteColor;
    _field.tintColor = UIColor.whiteColor;
    _field.font = [UIFont systemFontOfSize:17];
    _field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search"
        attributes:@{NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.45]}];
    _field.returnKeyType = UIReturnKeySearch;
    _field.keyboardAppearance = UIKeyboardAppearanceDark;
    _field.autocorrectionType = UITextAutocorrectionTypeNo;
    _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _field.clearButtonMode = UITextFieldViewModeNever;
    [self.content addSubview:_icon];
    [self.content addSubview:_field];
    [self.content addSubview:_mic];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _icon.frame = CGRectMake(14, (h - 22) / 2, 22, 22);
    _mic.frame = CGRectMake(w - 14 - 22, (h - 22) / 2, 22, 22);
    _field.frame = CGRectMake(44, 0, MAX(0, w - 44 - 44), h);
}
@end

#pragma mark - Pill di home screen

static GSGlassView *gsPill;
static BOOL gsPillSuppressed;

#pragma mark - Overlay controller

@interface GSController : UIViewController <UITextFieldDelegate, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)presentFromRect:(CGRect)rect;
- (void)dismissThen:(void (^)(void))then;
- (void)pillTapped;
@end

static UIImage *GSIcon(NSString *bid) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[bid]) return cache[bid];
    UIImage *raw = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:UIScreen.mainScreen.scale];
    if (!raw) return nil;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)]
        imageWithActions:^(UIGraphicsImageRendererContext *c) { [raw drawInRect:CGRectMake(0, 0, 40, 40)]; }];
    cache[bid] = img;
    return img;
}

@implementation GSController {
    UIWindow *_window, *_prevKey;
    UIVisualEffectView *_backdrop;
    UIView *_dim;
    GSBar *_bar;
    GSGlassView *_card;
    UITableView *_table;
    NSArray<NSDictionary *> *_allApps, *_results;
    CGRect _pillRect;
    CGFloat _kbTop;
    BOOL _dismissing, _kbSeen;
}

+ (instancetype)shared {
    static GSController *s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [GSController new]; });
    return s;
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    _backdrop = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    _backdrop.frame = self.view.bounds;
    _backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_backdrop];

    _dim = [[UIView alloc] initWithFrame:self.view.bounds];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_dim];

    _card = [[GSGlassView alloc] initWithFrame:CGRectZero];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorColor = [UIColor colorWithWhite:1 alpha:0.12];
    _table.rowHeight = 56;
    _table.dataSource = self;
    _table.delegate = self;
    _table.frame = _card.content.bounds;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_card.content addSubview:_table];
    [self.view addSubview:_card];

    _bar = [[GSBar alloc] initWithFrame:CGRectZero];
    _bar.field.delegate = self;
    [_bar.field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_bar];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bgTapped)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(bgTapped)];
    swipe.direction = UISwipeGestureRecognizerDirectionDown;
    swipe.delegate = self;
    [self.view addGestureRecognizer:swipe];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    return ![t.view isDescendantOfView:_bar] && ![t.view isDescendantOfView:_card];
}
- (void)bgTapped { [self dismissThen:nil]; }

#pragma mark Data

- (void)loadApps {
    NSMutableArray *out = [NSMutableArray array];
    @try {
        Class c = NSClassFromString(@"LSApplicationWorkspace");
        LSApplicationWorkspace *ws = [c performSelector:@selector(defaultWorkspace)];
        for (id p in [ws allInstalledApplications]) {
            NSString *bid = [p valueForKey:@"applicationIdentifier"];
            NSString *name = [p valueForKey:@"localizedName"];
            if (!bid.length || !name.length) continue;
            NSArray *tags = nil;
            @try { tags = [p valueForKey:@"appTags"]; } @catch (id e) {}
            if ([tags containsObject:@"hidden"]) continue;
            [out addObject:@{@"name": name, @"bid": bid}];
        }
    } @catch (id e) {}
    _allApps = out;
}

- (void)updateResults {
    NSString *q = [_bar.field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!q.length) { _results = @[]; return; }
    NSMutableArray *pre = [NSMutableArray array], *con = [NSMutableArray array];
    for (NSDictionary *a in _allApps) {
        NSRange r = [a[@"name"] rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch];
        if (r.location == NSNotFound) continue;
        [(r.location == 0 ? pre : con) addObject:a];
    }
    NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
    NSMutableArray *list = [NSMutableArray array];
    [list addObjectsFromArray:[pre sortedArrayUsingDescriptors:@[sd]]];
    [list addObjectsFromArray:[con sortedArrayUsingDescriptors:@[sd]]];
    if (list.count > 6) [list removeObjectsInRange:NSMakeRange(6, list.count - 6)];
    [list addObject:@{@"name": [NSString stringWithFormat:@"Search Web for “%@”", q], @"q": q}];
    _results = list;
}

- (void)textChanged {
    [self updateResults];
    [_table reloadData];
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ [self layoutCard]; } completion:nil];
}

#pragma mark Layout

- (void)layoutCard {
    CGFloat W = self.view.bounds.size.width;
    CGFloat top = self.view.safeAreaInsets.top + 8;
    CGFloat avail = MAX(0, CGRectGetMinY(_bar.frame) - 10 - top);
    CGFloat h = MIN(_results.count * 56.0, avail);
    _card.frame = CGRectMake(16, CGRectGetMinY(_bar.frame) - 10 - h, W - 32, h);
    _card.layer.cornerRadius = 26;
    _card.alpha = _results.count ? 1 : 0;
}

- (void)applyLayoutWithDuration:(double)d options:(UIViewAnimationOptions)o {
    [UIView animateWithDuration:d delay:0 options:o | UIViewAnimationOptionBeginFromCurrentState animations:^{
        CGFloat W = self.view.bounds.size.width;
        self->_bar.frame = CGRectMake(16, self->_kbTop - 10 - 46, W - 32, 46);
        self->_bar.layer.cornerRadius = 23;
        self->_bar.icon.alpha = self->_bar.field.alpha = self->_bar.mic.alpha = 1;
        [self layoutCard];
    } completion:nil];
}

- (void)kbChange:(NSNotification *)n {
    if (_dismissing || !_window) return;
    _kbSeen = YES;
    CGRect end = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat H = CGRectGetHeight(self.view.bounds);
    _kbTop = end.origin.y >= H - 1 ? H - self.view.safeAreaInsets.bottom : end.origin.y;
    double d = [n.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    NSUInteger c = [n.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue];
    [self applyLayoutWithDuration:d options:(UIViewAnimationOptions)(c << 16)];
}

#pragma mark Present / dismiss

- (void)pillTapped {
    CGRect r = gsPill ? [gsPill convertRect:gsPill.bounds toView:nil] : CGRectZero;
    [self presentFromRect:r];
}

- (void)presentFromRect:(CGRect)rect {
    if (_window) return;
    CGRect scr = UIScreen.mainScreen.bounds;
    if (CGRectIsEmpty(rect)) rect = CGRectMake(CGRectGetMidX(scr) - 46, CGRectGetHeight(scr) - 150, 92, 30);
    _pillRect = rect; _dismissing = NO; _kbSeen = NO;
    _prevKey = UIApplication.sharedApplication.keyWindow;
    [self loadApps];

    _window = [[UIWindow alloc] initWithFrame:scr];
    _window.windowLevel = UIWindowLevelAlert + 50;
    _window.backgroundColor = UIColor.clearColor;
    _window.rootViewController = self;
    [_window makeKeyAndVisible];
    [self.view layoutIfNeeded];

    gsPillSuppressed = YES; gsPill.hidden = YES;
    _results = @[]; [_table reloadData];
    _bar.field.text = @"";
    _backdrop.alpha = 0; _dim.alpha = 0; _card.alpha = 0;
    _bar.frame = rect; _bar.layer.cornerRadius = rect.size.height / 2;
    _bar.icon.alpha = _bar.field.alpha = _bar.mic.alpha = 0;
    _kbTop = CGRectGetHeight(scr) - 300;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbChange:)
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [UIView animateWithDuration:0.30 animations:^{ self->_backdrop.alpha = 1; self->_dim.alpha = 1; }];
    [_bar.field becomeFirstResponder];

    // cadangan kalau notifikasi keyboard tidak datang (mis. keyboard hardware)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_kbSeen && !self->_dismissing && self->_window)
            [self applyLayoutWithDuration:0.3 options:UIViewAnimationOptionCurveEaseInOut];
    });
}

- (void)dismissThen:(void (^)(void))then {
    if (!_window || _dismissing) return;
    _dismissing = YES;
    [_bar.field resignFirstResponder];
    [UIView animateWithDuration:0.32 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self->_backdrop.alpha = 0; self->_dim.alpha = 0; self->_card.alpha = 0;
        self->_bar.frame = self->_pillRect;
        self->_bar.layer.cornerRadius = self->_pillRect.size.height / 2;
        self->_bar.icon.alpha = self->_bar.field.alpha = self->_bar.mic.alpha = 0;
    } completion:^(BOOL f) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        self->_window.hidden = YES;
        self->_window.rootViewController = nil;
        self->_window = nil;
        [self->_prevKey makeKeyWindow];
        self->_prevKey = nil;
        gsPillSuppressed = NO; gsPill.hidden = NO;
        if (then) then();
    }];
}

- (void)launch:(NSDictionary *)d {
    [self dismissThen:^{
        NSString *bid = d[@"bid"];
        if (bid) {
            Class c = NSClassFromString(@"LSApplicationWorkspace");
            LSApplicationWorkspace *ws = [c performSelector:@selector(defaultWorkspace)];
            [ws openApplicationWithBundleID:bid];
        } else {
            NSString *q = [d[@"q"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
            NSURL *u = [NSURL URLWithString:[@"https://www.google.com/search?q=" stringByAppendingString:q ?: @""]];
            if (u) [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
        }
    }];
}

#pragma mark Text field / table

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    if (_results.count) [self launch:_results.firstObject]; else [self dismissThen:nil];
    return NO;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _results.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
        cell.backgroundColor = UIColor.clearColor;
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.textLabel.font = [UIFont systemFontOfSize:17];
        cell.imageView.layer.cornerRadius = 9;
        cell.imageView.clipsToBounds = YES;
        cell.selectedBackgroundView = [UIView new];
        cell.selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    }
    NSDictionary *d = _results[ip.row];
    cell.textLabel.text = d[@"name"];
    if (d[@"bid"]) { cell.imageView.image = GSIcon(d[@"bid"]); cell.imageView.tintColor = nil; }
    else { cell.imageView.image = [GSSymbol(@"magnifyingglass", 20) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]; cell.imageView.tintColor = UIColor.whiteColor; }
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:NO];
    [self launch:_results[ip.row]];
}
@end

#pragma mark - Hook: pill di atas dock

%hook SBRootFolderView
- (void)layoutSubviews {
    %orig;
    UIView *root = (UIView *)self;
    if (!gsPill) {
        gsPill = [[GSGlassView alloc] initWithFrame:CGRectMake(0, 0, 92, 30)];
        gsPill.layer.cornerRadius = 15;
        UIImageView *ic = [[UIImageView alloc] initWithImage:GSSymbol(@"magnifyingglass", 11)];
        ic.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
        ic.frame = CGRectMake(14, 8, 14, 14);
        ic.contentMode = UIViewContentModeCenter;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(32, 0, 52, 30)];
        l.text = @"Search";
        l.textColor = [UIColor colorWithWhite:1 alpha:0.9];
        l.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightMedium];
        [gsPill.content addSubview:ic];
        [gsPill.content addSubview:l];
        [gsPill addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:[GSController shared] action:@selector(pillTapped)]];
    }
    if (gsPill.superview != root) [root addSubview:gsPill];

    UIView *dock = nil;
    @try { if ([root respondsToSelector:NSSelectorFromString(@"dockView")]) dock = [root valueForKey:@"dockView"]; } @catch (id e) {}
    CGFloat y = CGRectGetHeight(root.bounds) - 150;
    if ([dock isKindOfClass:UIView.class]) {
        CGRect df = [root convertRect:dock.bounds fromView:dock];
        y = CGRectGetMinY(df) - 16 - 30;
        gsPill.alpha = dock.alpha;
    }
    gsPill.frame = CGRectMake(CGRectGetMidX(root.bounds) - 46, y, 92, 30);
    gsPill.layer.cornerRadius = 15;
    gsPill.hidden = gsPillSuppressed || ([dock isKindOfClass:UIView.class] && dock.hidden);
    [root bringSubviewToFront:gsPill];
}
%end

#pragma mark - Swipe-down: ganti Spotlight bawaan (dikonfigurasi lewat file, lihat README)

static void GSPresentFromNative(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[GSController shared] pillTapped]; });
}
static void GSNoopV(id self, SEL _cmd) { GSPresentFromNative(); }
static BOOL GSNoopB(id self, SEL _cmd) { GSPresentFromNative(); return YES; }

// Baca /var/mobile/GlassSearch_hooks.txt: tiap baris "NamaKelas namaSelector"
static void GSInstallConfiguredHooks(void) {
    NSString *txt = [NSString stringWithContentsOfFile:@"/var/mobile/GlassSearch_hooks.txt" encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [txt componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *ln = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!ln.length || [ln hasPrefix:@"#"]) continue;
        NSArray *p = [ln componentsSeparatedByString:@" "];
        if (p.count != 2) continue;
        Class c = NSClassFromString(p[0]);
        SEL s = NSSelectorFromString(p[1]);
        Method m = c ? class_getInstanceMethod(c, s) : NULL;
        if (!m) continue;
        char rt[8] = {0};
        method_getReturnType(m, rt, sizeof rt);
        IMP imp = rt[0] == 'v' ? (IMP)GSNoopV : (rt[0] == 'B' ? (IMP)GSNoopB : NULL);
        if (imp) class_replaceMethod(c, s, imp, method_getTypeEncoding(m));
    }
}

// Kalau file /var/mobile/GlassSearch_dump ada, tulis daftar kelas/metode Search & Spotlight
static void GSDumpIfRequested(void) {
    if (![NSFileManager.defaultManager fileExistsAtPath:@"/var/mobile/GlassSearch_dump"]) return;
    NSMutableString *out = [NSMutableString string];
    unsigned n = 0;
    Class *list = objc_copyClassList(&n);
    for (unsigned i = 0; i < n; i++) {
        const char *nm = class_getName(list[i]);
        if (!(strncmp(nm, "SB", 2) == 0 || strncmp(nm, "SPUI", 4) == 0)) continue;
        if (!(strcasestr(nm, "search") || strcasestr(nm, "spotlight"))) continue;
        [out appendFormat:@"%s\n", nm];
        unsigned mc = 0;
        Method *ms = class_copyMethodList(list[i], &mc);
        for (unsigned j = 0; j < mc; j++)
            [out appendFormat:@"    %s\n", sel_getName(method_getName(ms[j]))];
        free(ms);
    }
    free(list);
    [out writeToFile:@"/var/mobile/GlassSearch_classes.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

%ctor {
    @autoreleasepool {
        GSDumpIfRequested();
        GSInstallConfiguredHooks();
    }
}
