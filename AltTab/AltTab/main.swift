//
//  main.swift
//  AltTab — Windows-style Window Switcher for macOS
//
//  Application entry point. Creates the NSApplication instance and wires
//  the AppDelegate manually (no storyboard/nib). This is the standard
//  pattern for programmatic-only macOS menu bar utilities.
//
//  Author:  Sergio Farfan <sergio.farfan@gmail.com>
//  Version: 1.0.0
//  Date:    2026-03-17
//  License: MIT
//

import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
