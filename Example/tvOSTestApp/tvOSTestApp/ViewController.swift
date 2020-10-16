//
//  ViewController.swift
//  tvOSTestApp
//
//  Created by Chris Hubbard on 10/15/20.
//

import UIKit

class ViewController: UIViewController {
    
    // grab a reference to the shared GA MP client
    let mpClient = GA4MPClient.shared

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure the GA MP client as needed
        mpClient.setNonPersonalizedAds(false)
        mpClient.debugMode = true
        mpClient.useValidationEndpoint = true
        mpClient.setDefaultEventParameters(["default1": "value", "default2": "another value"])
    }

    @IBAction func setUserPropertyClick(_ sender: UIButton) {
        mpClient.setUserProperty("test value", forName: "tvos_test_prop")
    }
    
    @IBAction func clearUserPropertyClick(_ sender: UIButton) {
        mpClient.setUserProperty(nil, forName: "tvos_test_prop")
    }
    
    @IBAction func signInClick(_ sender: UIButton) {
        mpClient.setUserLoggedIn(true)
        mpClient.setUserID("test_tvos_user")
    }
    
    @IBAction func signOutClick(_ sender: UIButton) {
        mpClient.setUserLoggedIn(false)
        mpClient.setUserID(nil)
    }
    
    @IBAction func logEventClick(_ sender: UIButton) {
        // note that when these events are logged, the default parameters will be added
        mpClient.logEvent("tvos_event_with_params", parameters: ["screen_name": "the screen", "pointless_message": "yes it is"])
        mpClient.logEvent("tvos_event_no_params", parameters: nil)
    }
    
}

