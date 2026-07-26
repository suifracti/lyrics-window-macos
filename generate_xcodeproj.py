import os

pbxproj_content = """// !$*RA_UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		110000012D83400100000001 /* Main.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000012D83400100000000 /* Main.swift */; };
		110000022D83400100000001 /* Models.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000022D83400100000000 /* Models.swift */; };
		110000032D83400100000001 /* MockData.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000032D83400100000000 /* MockData.swift */; };
		110000042D83400100000001 /* PlaybackState.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000042D83400100000000 /* PlaybackState.swift */; };
		110000052D83400100000001 /* WindowManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000052D83400100000000 /* WindowManager.swift */; };
		110000062D83400100000001 /* LyricsViews.swift in Sources */ = {isa = PBXBuildFile; fileRef = 110000062D83400100000000 /* LyricsViews.swift */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		110000002D83400000000000 /* SpotifyLyrics.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SpotifyLyrics.app; sourceTree = BUILT_PRODUCTS_DIR; };
		110000012D83400100000000 /* Main.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Main.swift; sourceTree = "<group>"; };
		110000022D83400100000000 /* Models.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Models/Models.swift; sourceTree = "<group>"; };
		110000032D83400100000000 /* MockData.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Services/MockData.swift; sourceTree = "<group>"; };
		110000042D83400100000000 /* PlaybackState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Services/PlaybackState.swift; sourceTree = "<group>"; };
		110000052D83400100000000 /* WindowManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Windows/WindowManager.swift; sourceTree = "<group>"; };
		110000062D83400100000000 /* LyricsViews.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Views/LyricsViews.swift; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		110000002D83400000000001 = {
			isa = PBXGroup;
			children = (
				110000002D83400000000002 /* SpotifyLyrics */,
				110000002D83400000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		110000002D83400000000002 /* SpotifyLyrics */ = {
			isa = PBXGroup;
			children = (
				110000012D83400100000000 /* Main.swift */,
				110000022D83400100000000 /* Models.swift */,
				110000032D83400100000000 /* MockData.swift */,
				110000042D83400100000000 /* PlaybackState.swift */,
				110000052D83400100000000 /* WindowManager.swift */,
				110000062D83400100000000 /* LyricsViews.swift */,
			);
			path = SpotifyLyrics;
			sourceTree = "<group>";
		};
		110000002D83400000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				110000002D83400000000000 /* SpotifyLyrics.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		110000002D83400000000004 /* SpotifyLyrics */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 110000002D83400000000007 /* Build configuration list for PBXNativeTarget "SpotifyLyrics" */;
			buildPhases = (
				110000002D83400000000005 /* Sources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = SpotifyLyrics;
			productName = SpotifyLyrics;
			productReference = 110000002D83400000000000 /* SpotifyLyrics.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		110000002D83400000000006 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					110000002D83400000000004 = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = 110000002D8340000000000A /* Build configuration list for PBXProject "SpotifyLyrics" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 110000002D83400000000001;
			productRefGroup = 110000002D83400000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				110000002D83400000000004 /* SpotifyLyrics */,
			);
		};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		110000002D83400000000005 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				110000012D83400100000001 /* Main.swift in Sources */,
				110000022D83400100000001 /* Models.swift in Sources */,
				110000032D83400100000001 /* MockData.swift in Sources */,
				110000042D83400100000001 /* PlaybackState.swift in Sources */,
				110000052D83400100000001 /* WindowManager.swift in Sources */,
				110000062D83400100000001 /* LyricsViews.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		110000002D83400000000008 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHighResolutionCapable = YES;
				INFOPLIST_KEY_LSMinimumSystemVersion = "14.0";
				INFOPLIST_KEY_CFBundleDisplayName = SpotifyLyrics;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.spotifylyrics.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		110000002D83400000000009 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHighResolutionCapable = YES;
				INFOPLIST_KEY_LSMinimumSystemVersion = "14.0";
				INFOPLIST_KEY_CFBundleDisplayName = SpotifyLyrics;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.spotifylyrics.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		110000002D8340000000000B /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		110000002D8340000000000C /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CODE_SIGN_IDENTITY = "-";
				COPY_PHASE_STRIP = YES;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_FAST_MATH = YES;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		110000002D83400000000007 /* Build configuration list for PBXNativeTarget "SpotifyLyrics" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				110000002D83400000000008 /* Debug */,
				110000002D83400000000009 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		110000002D8340000000000A /* Build configuration list for PBXProject "SpotifyLyrics" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				110000002D8340000000000B /* Debug */,
				110000002D8340000000000C /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 110000002D83400000000006 /* Project object */;
}
"""

os.makedirs("SpotifyLyrics.xcodeproj", exist_ok=True)
with open("SpotifyLyrics.xcodeproj/project.pbxproj", "w") as f:
    f.write(pbxproj_content)

print("SpotifyLyrics.xcodeproj created successfully.")
