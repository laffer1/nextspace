/*
  Copyright (C) 2015-2017 Sergii Stoian <stoyan255@ukr.net>

  This file is a part of Terminal.app. Terminal.app is free software; you
  can redistribute it and/or modify it under the terms of the GNU General
  Public License as published by the Free Software Foundation; version 2
  of the License. See COPYING or main.m for more information.
*/

#include <AppKit/AppKit.h>

#include "Preferences.h"

@interface LinuxPrefs : NSObject <PrefsModule>
{
  id charsetBtn;
  id handleMulticellBtn;
  id commandKeyBtn;
  id escapeKeyBtn;
  id window;
  id view;
}
- (void)setDefault:(id)sender;
- (void)showDefault:(id)sender;
- (void)setWindow:(id)sender;
@end
