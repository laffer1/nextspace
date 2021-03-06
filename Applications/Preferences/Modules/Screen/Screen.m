/*
  Screen.m

  Controller class for Screen preferences bundle

  Author:	Sergii Stoian <stoyan255@ukr.net>
  Date:		28 Nov 2015

  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 2 of
  the License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with this program; if not, write to:

  Free Software Foundation, Inc.
  59 Temple Place - Suite 330
  Boston, MA  02111-1307, USA
*/
#import <AppKit/NSApplication.h>
#import <AppKit/NSNibLoading.h>
#import <AppKit/NSView.h>
#import <AppKit/NSBox.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSButton.h>
#import <AppKit/NSGraphics.h>

#import <AppKit/PSOperators.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>

#import <AppKit/NSScreen.h>
#import <AppKit/NSPanel.h>

#import <NXSystem/NXDisplay.h>
#import <NXSystem/NXPower.h>

#import "Screen.h"

@implementation ScreenPreferences
@synthesize dockImage;
@synthesize appIconYardImage;
@synthesize iconYardImage;

static NXPower *power = nil;

- (id)init
{
  NSString *imagePath;
  NSBundle *bundle;
  
  self = [super init];
  
  bundle = [NSBundle bundleForClass:[self class]];
  
  imagePath = [bundle pathForResource:@"Screen" ofType:@"tiff"];
  image = [[NSImage alloc] initWithContentsOfFile:imagePath];

  imagePath = [bundle pathForResource:@"dock" ofType:@"tiff"];
  dockImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
  imagePath = [bundle pathForResource:@"appiconyard" ofType:@"tiff"];
  appIconYardImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
  imagePath = [bundle pathForResource:@"iconyard" ofType:@"tiff"];
  iconYardImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
      
  return self;
}

- (void)dealloc
{
  NSLog(@"Screen: -dealloc");
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  [image release];
  [dockImage release];
  [appIconYardImage release];
  [iconYardImage release];
  
  [displayBoxList release];

  [systemScreen release];
  
  [super dealloc];
}

- (void)awakeFromNib
{
  [view retain];
  [window release];

  systemScreen = [[NXScreen alloc] init];
  // Get info about monitors and layout
  displayBoxList = [[NSMutableArray alloc] init];
  [self updateDisplayBoxList];

  [[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(screenDidUpdate:)
           name:NXScreenDidUpdateNotification
         object:nil];

  // Open/close lid events
  power = [NXPower new];
  [power startEventsMonitor];
  [[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(lidDidChange:)
           name:NXPowerLidDidChangeNotification
         object:power];
}

- (NSView *)view
{
  if (view == nil)
    {
      if (![NSBundle loadNibNamed:@"Screen" owner:self])
        {
          NSLog (@"Screen.preferences: Could not load NIB, aborting.");
          return nil;
        }
    }
  
  return view;
}

- (NSString *)buttonCaption
{
  return @"Screen Preferences";
}

- (NSImage *)buttonImage
{
  return image;
}

//
// Action methods
//
- (void)displayBoxClicked:(DisplayBox *)sender
{
  [sender setSelected:YES];
  selectedBox = sender;
  for (DisplayBox *db in displayBoxList)
    {
      if (db != sender) [db setSelected:NO];
    }

  [setMainBtn setEnabled:(![sender isMain]&&[sender isActive])];
  
  [setStateBtn setTitle:[sender isActive] ? @"Disable" : @"Enable"];
  
  if (([sender isActive] &&
       [[systemScreen activeDisplays] count] > 1) ||
      (![sender isActive] && ![NXPower isLidClosed]))
    {
      [setStateBtn setEnabled:YES];
    }
  else
    {
      [setStateBtn setEnabled:NO];
    }  
}

- (void)setMainDisplay:(id)sender
{
  NXDisplay *display;
  
  display = [systemScreen displayWithName:[selectedBox name]];
  // NXScreen -> [NXDisplay setMain:] -> [NXScreen _refreshDisplaysInfo]
  // [NXDisplay setMain:] will generate NXScreenDidChangeNotification.
  [systemScreen setMainDisplay:display];
}

- (void)setDisplayState:(id)sender
{
  NXDisplay *display;
  
  display = [systemScreen displayWithName:[selectedBox name]];
  
  if ([[sender title] isEqualToString:@"Disable"])
    {
      // [systemScreen deactivateDisplay:[selectedBox display]];
      [systemScreen deactivateDisplay:display];
    }
  else
    {
      // [systemScreen activateDisplay:[selectedBox display]];
      [systemScreen activateDisplay:display];
    }
}

- (void)arrangeDisplays:(id)sender
{
  [self updateDisplayBoxList];
}

//
// Helper methods
//

- (void)selectFirstEnabledMonitor
{
  DisplayBox *db = nil;
  
  for (db in displayBoxList)
    {
      // if ([[db display] isActive])
      if ([[systemScreen displayWithName:[db name]] isActive])
        {
          [db setSelected:YES];
          break;
        }
    }

  [self displayBoxClicked:db];
}

- (void)updateDisplayBoxList
{
  NSArray *displays;
  NSRect  canvasRect = [[canvas contentView] frame];
  NSRect  displayRect, dBoxRect;
  CGFloat dMaxWidth = 0.0, dMaxHeight = 0.0;
  CGFloat scaleWidth, scaleHeight;
  DisplayBox *dBox;

  NSLog(@"Screen: update display box list.");

  // Clear view and array
  for (dBox in displayBoxList)
    {
      [dBox removeFromSuperview];
    }
  [displayBoxList removeAllObjects];
  
  displays = [systemScreen connectedDisplays];
  
  // Calculate scale factor
  for (NXDisplay *d in displays)
    {
      displayRect = [d frame];
      if (dMaxWidth < displayRect.size.width ||
          dMaxHeight < displayRect.size.height)
        {
          dMaxWidth = displayRect.size.width;
          dMaxHeight = displayRect.size.height;
        }
    }
  scaleWidth = (canvasRect.size.width/dMaxWidth) / 3;
  scaleHeight = (canvasRect.size.height/dMaxHeight) / 3;
  scaleFactor = (scaleWidth < scaleHeight) ? scaleWidth : scaleHeight;

  // Create and add display boxes
  for (NXDisplay *d in displays)
    {
      displayRect = [d frame];
      if ([d isActive] == NO)
        {
          NSDictionary *res = [[d allResolutions] objectAtIndex:0];
          NSSize       dSize;
          
          dSize = NSSizeFromString([res objectForKey:NXDisplaySizeKey]);
          displayRect.size.width = dSize.width;
          displayRect.size.height = dSize.height;
        }
      
      dBoxRect.origin.x = floor(displayRect.origin.x*scaleFactor);
      dBoxRect.origin.y = floor(displayRect.origin.y*scaleFactor);
      dBoxRect.size.width = floor(displayRect.size.width*scaleFactor);
      dBoxRect.size.height = floor(displayRect.size.height*scaleFactor);

      dBox = [[DisplayBox alloc] initWithFrame:dBoxRect display:d owner:self];
      [dBox setDisplayFrame:displayRect];
      [dBox setName:[d outputName]];
      [dBox setActive:[d isActive]];
      [dBox setMain:[d isMain]];
      if ([displays indexOfObject:d] != 0)
        {
          [canvas addSubview:dBox
                  positioned:NSWindowAbove
                  relativeTo:[displayBoxList lastObject]];
        }
      else
        {
          [canvas addSubview:dBox];
        }
      [displayBoxList addObject:dBox];
      [dBox release];
    }

  [self arrangeDisplayBoxes];
  [self selectFirstEnabledMonitor];
}

// edge: NSMinXEdge, NSMaxXEdge, NSMinYEdge, NSMaxYEdge
- (NSPoint)pointAtLayoutEdge:(NSInteger)edge
                      forBox:(DisplayBox *)box
{
  NSPoint point = NSMakePoint(0,0);
  NSRect  dRect;
  
  for (DisplayBox *dBox in displayBoxList)
    {
      if (dBox == box) continue;
      
      dRect = [dBox frame];
      if (edge == NSMaxXEdge) // right
        {
          point.x = MAX(NSMaxX(dRect), point.x);
        }
      else if (edge == NSMaxYEdge) // top
        {
          point.y = MAX(NSMaxY(dRect), point.y);
        }
    }

  return point;
}

- (void)arrangeDisplayBoxes
{
  NSRect  dRect, sRect = [canvas frame];
  NSSize  screenSize = [systemScreen sizeInPixels];
  CGFloat xOffset, yOffset;

  // Include inactive display into screen size
  for (DisplayBox *dBox in displayBoxList)
    {
      dRect = [dBox frame];
      if ([dBox isActive] == NO)
        {
          screenSize.width += [dBox displayFrame].size.width;
        }
    }
  xOffset = floor((sRect.size.width - (screenSize.width * scaleFactor))/2);
  
  // Align boxes at that top edge
  yOffset = floor(sRect.size.height -
                  (sRect.size.height - (screenSize.height * scaleFactor))/2);

  for (DisplayBox *dBox in displayBoxList)
    {
      dRect = [dBox frame];
      if ([dBox isActive] == NO)
        {
          // Place inactive display at right from active
          dRect.origin.x = [self pointAtLayoutEdge:NSMaxXEdge forBox:dBox].x;
        }
      if ([dBox isActive] == YES || [displayBoxList indexOfObject:dBox] == 0)
        {
          dRect.origin.x += xOffset;
        }
      dRect.origin.y += (yOffset - dRect.size.height);
      [dBox setFrame:dRect];
    }
}

//
// Notifications
//
- (void)screenDidUpdate:(NSNotification *)aNotif
{
  NSLog(@"Screen: XRandR screen resources was updated, refreshing...");
  [self updateDisplayBoxList];
}

- (void)lidDidChange:(NSNotification *)aNotif
{
  NXDisplay *builtinDisplay = nil;

  // for (DisplayBox *db in displayBoxList)
  for (NXDisplay *d in [systemScreen connectedDisplays])
    {
      if ([d isBuiltin])
        {
          builtinDisplay = d;
          break;
        }
    }
  
  if (builtinDisplay)
    {
      if (![[aNotif object] isLidClosed] && ![builtinDisplay isActive])
        {
          NSLog(@"Screen: activating display %@", [builtinDisplay outputName]);
          [systemScreen activateDisplay:builtinDisplay];
        }
      else if ([[aNotif object] isLidClosed] && [builtinDisplay isActive])
        {
          NSLog(@"Screen: DEactivating display %@",
                [builtinDisplay outputName]);
          [systemScreen deactivateDisplay:builtinDisplay];
        }
    }
}

@end

@implementation ScreenCanvas

- initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame:frameRect];
  [self setBorderType:NSBezelBorder];
  [self setTitlePosition:NSNoTitle];
  [self setFillColor:[NSColor grayColor]];
  [self setContentViewMargins:NSMakeSize(0, 0)];

  return self;
}

- (void)drawRect:(NSRect)rect
{
  [super drawRect:rect];

  [_fill_color set];
  NSRectFill([[self contentView] frame]);

  // CGFloat f, lines = rect.size.height;
  // CGFloat pattern[2] = {1};
  // [[NSColor darkGrayColor] set];
  // PSsetdash(pattern, 1, 0);
  // for (f=2; f<lines-2; f++)
  //   {
  //     PSmoveto(2, f);
  //     PSlineto(rect.size.width, f);
  //     f++;
  //     PSmoveto(3, f);
  //     PSlineto(rect.size.width-2, f);
  //   }
  // PSstroke();
}

- (void)mouseDown:(NSEvent *)theEvent
            inBox:(DisplayBox *)box
{
  // NSArray    *boxes = [self subviews];
  NSRect     boxRect = [box frame];
  NSPoint    location, initialLocation, lastLocation;
  
  NSWindow   *window = [self window];
  NSRect     superFrame = [self frame];
  NSRect     displayFrame = [box displayFrame];
  NSPoint    initialOrigin, boxOrigin;
  NSUInteger eventMask = (NSLeftMouseDownMask | NSLeftMouseUpMask
                          | NSPeriodicMask | NSOtherMouseUpMask
                          | NSRightMouseUpMask);
  NSDate     *theDistantFuture = [NSDate distantFuture];
  BOOL       done = NO;

  initialOrigin = boxOrigin = boxRect.origin;
  initialLocation = lastLocation = [theEvent locationInWindow];

  [NSEvent startPeriodicEventsAfterDelay:0.02 withPeriod:0.02];

  while (!done)
    {
      theEvent = [NSApp nextEventMatchingMask:eventMask
                                    untilDate:theDistantFuture
                                       inMode:NSEventTrackingRunLoopMode
                                      dequeue:YES];

      switch ([theEvent type])
        {
        case NSRightMouseUp:
        case NSOtherMouseUp:
        case NSLeftMouseUp:
          // NSLog(@"Mouse UP.");
          done = YES;
          break;
        case NSPeriodic:
          location = [window mouseLocationOutsideOfEventStream];
          if (NSEqualPoints(location, lastLocation) == NO &&
              (fabs(location.x - initialLocation.x) > 5 ||
               fabs(location.y - initialLocation.y) > 5))
            {
              if (displayFrame.origin.x > 0 ||
                  boxOrigin.x > initialOrigin.x ||
                  (location.x - lastLocation.x) > 0)
                {
                  boxOrigin.x += (location.x - lastLocation.x);
                  if (boxOrigin.x < 0)
                    {
                      boxOrigin.x = 0;
                    }
                  else if ((boxOrigin.x + boxRect.size.width)
                           > superFrame.size.width)
                    {
                      boxOrigin.x =
                        superFrame.size.width - boxRect.size.width;
                    }
                }
                  
              boxOrigin.y += (location.y - lastLocation.y);
              if (boxOrigin.y < 0)
                {
                  boxOrigin.y = 0;
                }
              else if ((boxOrigin.y + boxRect.size.height)
                       > superFrame.size.height)
                {
                  boxOrigin.y = superFrame.size.height - boxRect.size.height;
                }
                  
              [box setFrameOrigin:boxOrigin];
              [self setNeedsDisplay:YES];
                  
              lastLocation = location;
            }
          break;

        default:
          break;
        }
    }
  [NSEvent stopPeriodicEvents];

  if (NSEqualPoints(initialLocation, lastLocation) == YES)
    {
      [owner displayBoxClicked:box];
    }
}

@end

@implementation DisplayBox

- initWithFrame:(NSRect)frameRect
        display:(NXDisplay *)aDisplay
          owner:(id)prefs
{
  NSRect nameRect;
  
  self = [super initWithFrame:frameRect];
  [self setBorderType:NSLineBorder];
  [self setTitlePosition:NSNoTitle];
  [self setContentViewMargins:NSMakeSize(1, 1)];

  owner = prefs;
  
  // display = aDisplay;

  nameRect = frameRect;
  nameRect.size.height = 15;
  nameRect.origin.x = 0;
  nameRect.origin.y = (frameRect.size.height - nameRect.size.height)/2;

  nameField = [[NSTextField alloc] initWithFrame:nameRect];
  [nameField setEditable:NO];
  [nameField setSelectable:NO];
  [nameField setDrawsBackground:NO];
  [nameField setTextColor:[NSColor whiteColor]];
  [nameField setAlignment:NSCenterTextAlignment];
  [nameField setBezeled:NO];

  [self addSubview:nameField];
  [nameField release];
  
  isMainDisplay = NO;

  return self;
}

- (void)dealloc
{
  NSLog(@"Screen: display box %@: -dealloc", [nameField stringValue]);
  [super dealloc];
}

- (void)setDisplayFrame:(NSRect)rect
{
  displayFrame = rect;
}

- (NSRect)displayFrame
{
  return displayFrame;
}

- (void)setName:(NSString *)name
{
  [nameField setStringValue:name];
}

- (NSString *)name
{
  return [nameField stringValue];
}

- (void)setActive:(BOOL)active
{
  NSColor *color;
  
  if (active)
    {
      // TODO: get desktop background color
      color = [NSColor colorWithDeviceRed:83.0/255.0
                                    green:83.0/255.0
                                     blue:116.0/255.0
                                    alpha:1];
      [nameField setTextColor:[NSColor whiteColor]];
    }
  else
    {
      color = [NSColor darkGrayColor];
      [nameField setTextColor:[NSColor lightGrayColor]];
    }
  ASSIGN(bgColor, color);
  
  isActiveDisplay = active;
  
  [[self superview] setNeedsDisplay:YES];
}

- (BOOL)isActive
{
  return isActiveDisplay;
}

- (void)setMain:(BOOL)isMain
{
  isMainDisplay = isMain;
  [[self superview] setNeedsDisplay:YES];
}

- (BOOL)isMain
{
  return isMainDisplay;
}

- (void)setSelected:(BOOL)selected
{
  isSelected = selected;
  [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)theEvent
{
  if ([theEvent clickCount] >= 2)
    {
      // Set main display
    }
  else
    {
      [(ScreenCanvas *)[[self superview] superview] mouseDown:theEvent
                                                        inBox:self];
    }
}

- (void)drawRect:(NSRect)rect
{
  [super drawRect:rect];

  [bgColor set];
  NSRectFill([[self contentView] frame]);

  // Draw red frame
  if (isSelected)
    {
      NSColor *selColor;

      selColor = [NSColor colorWithDeviceRed:1.0
                                       green:221.0/255.0
                                        blue:0.0
                                       alpha:1];

      // [[NSColor yellowColor] set];
      [selColor set];
      PSnewpath();
      PSmoveto(1.5,1.5);
      PSlineto(1.5, rect.size.height-1.5);
      PSlineto(rect.size.width-1.5, rect.size.height-1.5);
      PSlineto(rect.size.width-1.5, 1.5);
      PSlineto(1.5, 1.5);
      PSstroke();
    }

  if (!isActiveDisplay) return;
  
  // Draw dock and icon yard
  NSSize  iSize;
  NSPoint iPoint;
  if (isMainDisplay)
    {
      iSize = [owner.dockImage size];
      iPoint = NSMakePoint(rect.size.width-iSize.width-3,
                           rect.size.height-iSize.height-3);
      [[owner dockImage] compositeToPoint:iPoint
                                operation:NSCompositeSourceOver];
      
      iSize = [[owner appIconYardImage] size];
      iPoint = NSMakePoint(3,3);
      [[owner appIconYardImage] compositeToPoint:iPoint
                                       operation:NSCompositeSourceOver];
    }
  else
    {
      iPoint = NSMakePoint(3,3);
      iSize = [[owner iconYardImage] size];
      [[owner iconYardImage] compositeToPoint:iPoint
                                    operation:NSCompositeSourceOver];
      iPoint.x += iSize.width;
      [[owner iconYardImage] compositeToPoint:iPoint
                                    operation:NSCompositeSourceOver];
    }
}

@end
