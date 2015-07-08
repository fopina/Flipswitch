#import <FSSwitchDataSource.h>
#import <FSSwitchPanel.h>

#ifndef CTREGISTRATION_H_
extern CFStringRef const kCTRegistrationDataStatusChangedNotification;
extern CFStringRef const kCTRegistrationDataRateUnknown;
extern CFStringRef const kCTRegistrationDataRate2G;
extern CFStringRef const kCTRegistrationDataRate3G;
extern CFStringRef const kCTRegistrationDataRate4G;
CFArrayRef CTRegistrationCopySupportedDataRates();
CFStringRef CTRegistrationGetCurrentMaxAllowedDataRate();
void CTRegistrationSetMaxAllowedDataRate(CFStringRef dataRate);
#endif

#ifndef CTTELEPHONYCENTER_H_
CFNotificationCenterRef CTTelephonyCenterGetDefault();
void CTTelephonyCenterAddObserver(CFNotificationCenterRef center, const void *observer, CFNotificationCallback callBack, CFStringRef name, const void *object, CFNotificationSuspensionBehavior suspensionBehavior);
void CTTelephonyCenterRemoveObserver(CFNotificationCenterRef center, const void *observer, CFStringRef name, const void *object);
#endif

@interface DataSpeedSwitch : NSObject <FSSwitchDataSource> {
@private
  NSBundle *_bundle;
  NSString *_desiredDataRate;
}
@property (nonatomic, readonly) NSBundle *bundle;
@end

@interface DataSpeedSwitchSettingsViewController : UITableViewController <FSSwitchSettingsViewController> {
	NSArray *_supportedDataRates;
	NSInteger offDataRate;
	NSInteger onDataRate;
}
@end

static void FSDataStatusChanged(void);

@implementation DataSpeedSwitch

- (id)init
{
  [self release];
  return nil;
}

- (id)initWithBundle:(NSBundle *)bundle desiredDataRate:(NSString *)desiredDataRate
{
  if ((self = [super init])) {
    _bundle = [bundle retain];
    _desiredDataRate = [desiredDataRate copy];
  }

  return self;
}

- (void)dealloc
{
  [_bundle release];
  [_desiredDataRate release];
  [super dealloc];
}

@synthesize bundle = _bundle;

- (NSBundle *)bundleForSwitchIdentifier:(NSString *)switchIdentifier
{
  return _bundle;
}

- (FSSwitchState)stateForSwitchIdentifier:(NSString *)switchIdentifier
{
  NSArray *supportedDataRates = [(NSArray *)CTRegistrationCopySupportedDataRates() autorelease];
  NSUInteger desiredRateIndex = [supportedDataRates indexOfObject:_desiredDataRate];
  if (desiredRateIndex == NSNotFound)
    return FSSwitchStateOff;
  NSUInteger currentRateIndex = [supportedDataRates indexOfObject:(id)CTRegistrationGetCurrentMaxAllowedDataRate()];
  if (currentRateIndex == NSNotFound)
    return FSSwitchStateOff;
  return currentRateIndex >= desiredRateIndex;
}

- (void)applyState:(FSSwitchState)newState forSwitchIdentifier:(NSString *)switchIdentifier
{
  if (newState == FSSwitchStateIndeterminate)
    return;
  NSArray *supportedDataRates = [(NSArray *)CTRegistrationCopySupportedDataRates() autorelease];
  NSUInteger desiredRateIndex = [supportedDataRates indexOfObject:_desiredDataRate];
  if (desiredRateIndex == NSNotFound)
    return;
  NSUInteger currentRateIndex = [supportedDataRates indexOfObject:(id)CTRegistrationGetCurrentMaxAllowedDataRate()];
  if (currentRateIndex == NSNotFound)
    return;
  if (newState) {
    if (currentRateIndex < desiredRateIndex)
      CTRegistrationSetMaxAllowedDataRate((CFStringRef)_desiredDataRate);
  } else {
    if ((currentRateIndex >= desiredRateIndex) && desiredRateIndex)
      CTRegistrationSetMaxAllowedDataRate((CFStringRef)[supportedDataRates objectAtIndex:desiredRateIndex - 1]);
  }
}

- (void)applyAlternateActionForSwitchIdentifier:(NSString *)switchIdentifier
{
  NSURL *url = [NSURL URLWithString:(kCFCoreFoundationVersionNumber > 700.0f ? @"prefs:root=General&path=MOBILE_DATA_SETTINGS_ID" : @"prefs:root=General&path=Network")];
  [[FSSwitchPanel sharedPanel] openURLAsAlternateAction:url];
}

static DataSpeedSwitch *activeSwitch;

static void FSDataStatusChanged(void)
{
    NSString *bundlePath = nil;
    NSString *desiredDataRate = nil;
  CFArrayRef supportedDataRates = CTRegistrationCopySupportedDataRates();
  if (supportedDataRates) {
    if ([(NSArray *)supportedDataRates containsObject:(id)kCTRegistrationDataRate3G]) {
      if ([(NSArray *)supportedDataRates containsObject:(id)kCTRegistrationDataRate4G]) {
        bundlePath = @"/Library/Switches/LTE.bundle";
        desiredDataRate = (NSString *)kCTRegistrationDataRate4G;
      } else {
        bundlePath = @"/Library/Switches/3G.bundle";
        desiredDataRate = (NSString *)kCTRegistrationDataRate3G;
      }
    }
    CFRelease(supportedDataRates);
  }
  DataSpeedSwitch *oldActiveSwitch = activeSwitch;
  if (!bundlePath && !oldActiveSwitch)
    return;
  if (bundlePath) {
    if ([oldActiveSwitch.bundle.bundlePath isEqualToString:bundlePath]) {
      [[FSSwitchPanel sharedPanel] stateDidChangeForSwitchIdentifier:oldActiveSwitch.bundle.bundleIdentifier];
      return;
    }
    NSBundle *newBundle = [NSBundle bundleWithPath:bundlePath];
    activeSwitch = [[DataSpeedSwitch alloc] initWithBundle:newBundle desiredDataRate:desiredDataRate];
    [[FSSwitchPanel sharedPanel] registerDataSource:activeSwitch forSwitchIdentifier:newBundle.bundleIdentifier];
  } else {
    activeSwitch = nil;
  }
  if (oldActiveSwitch) {
    [[FSSwitchPanel sharedPanel] unregisterSwitchIdentifier:oldActiveSwitch.bundle.bundleIdentifier];
    [oldActiveSwitch release];
  }
}

- (Class <FSSwitchSettingsViewController>)settingsViewControllerClassForSwitchIdentifier:(NSString *)switchIdentifier
{
	Class result = nil;
	CFArrayRef supportedDataRates = CTRegistrationCopySupportedDataRates();
  if (supportedDataRates) {
    if ([(NSArray *)supportedDataRates containsObject:(id)kCTRegistrationDataRate4G]) {
				result = [DataSpeedSwitchSettingsViewController class];
      }
    CFRelease(supportedDataRates);
  }
  return result;
}

@end

@implementation DataSpeedSwitchSettingsViewController

- (id)init
{
	if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
		_supportedDataRates = [(NSArray *)CTRegistrationCopySupportedDataRates() autorelease];

		Boolean valid;
		CFIndex value = CFPreferencesGetAppIntegerValue(CFSTR("onDataRate"), CFSTR("com.a3tweaks.switch.dataspeed"), &valid);
		onDataRate = valid ? value : 2; // default to 4G, settings are only available if 4G is supported

		value = CFPreferencesGetAppIntegerValue(CFSTR("offDataRate"), CFSTR("com.a3tweaks.switch.dataspeed"), &valid);
		offDataRate = valid ? value : 1; // default to 3G
	}
  return self;
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{
	return [_supportedDataRates count];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)table
{
	return 2;
}

- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section
{
	switch (section) {
    case 0:
      return @"ON Data Rate";
    case 1:
      return @"OFF Data Rate";
    default:
      return nil;
	}
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"] ?: [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"] autorelease];
	cell.textLabel.text = [_supportedDataRates objectAtIndex:indexPath.row];
	CFIndex value = indexPath.section ? onDataRate : offDataRate;
  cell.accessoryType = (value == indexPath.row) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
  BOOL newValue = (cell.accessoryType == UITableViewCellAccessoryCheckmark);
  cell.accessoryType = newValue ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
}

@end

__attribute__((constructor))
static void constructor(void)
{
  /*
  crappy workaround on detecting whether or not to register the observer and the switch:
  - if stacktrace includes SpringBoard, GO!
  */
  for (NSString *symbol in [NSThread callStackSymbols]) {
    if ([symbol rangeOfString:@" SpringBoard " options:0].location != NSNotFound) {
      CTTelephonyCenterAddObserver(CTTelephonyCenterGetDefault(), NULL, (CFNotificationCallback)FSDataStatusChanged, kCTRegistrationDataStatusChangedNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
      FSDataStatusChanged();
    };
  };
}
