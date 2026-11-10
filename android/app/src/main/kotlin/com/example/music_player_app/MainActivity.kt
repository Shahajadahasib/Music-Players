package com.example.music_player_app

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity keeps the Flutter engine shared with the background
// audio service so playback, notification and lock-screen controls survive
// the activity being backgrounded.
class MainActivity : AudioServiceActivity()
