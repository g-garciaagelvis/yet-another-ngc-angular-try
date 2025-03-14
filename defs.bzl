load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@aspect_rules_js//npm:defs.bzl", "npm_package")
load("@aspect_bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory")
load("@aspect_rules_esbuild//esbuild:defs.bzl", "esbuild")
load("//tools:ng.bzl", "ng_esbuild", "ng_project")
load("@aspect_rules_ts//ts:defs.bzl", "ts_config")

# NOTE:
#  *_DEPS are propagated as deps of the final output
#  *_CONFIG are dependencies only of the architect actions and not propagated

# Global dependencies such as common config files, tools
COMMON_CONFIG = [
    "//:ng-config",
    "//:node_modules/@angular-devkit/build-angular",
    "//:node_modules/@angular-devkit/architect-cli",
]

# Common dependencies of Angular CLI applications
APPLICATION_CONFIG = [
    ":tsconfig.app.json",
    ":package.json",
]
APPLICATION_DEPS = [
    "//:node_modules/@angular/common",
    "//:node_modules/@angular/animations",
    "//:node_modules/@angular/core",
    "//:node_modules/@angular/router",
    "//:node_modules/@angular/platform-browser",
    "//:node_modules/@angular/platform-browser-dynamic",
    "//:node_modules/rxjs",
    "//:node_modules/tslib",
    "//:node_modules/zone.js",
]

# Common dependencies of Angular CLI libraries
LIBRARY_CONFIG = [
    ":tsconfig.lib.json",
    ":tsconfig.lib.prod.json",
    ":package.json",
]
LIBRARY_DEPS = [
    "//:node_modules/@angular/common",
    "//:node_modules/@angular/core",
    "//:node_modules/@angular/router",
    "//:node_modules/rxjs",
    "//:node_modules/tslib",
]

# Common dependencies of Angular CLI test suites
TEST_CONFIG = [
    ":tsconfig.spec.json",
    "//:node_modules/@types/jasmine",
    "//:node_modules/karma-chrome-launcher",
    "//:node_modules/karma",
    "//:node_modules/karma-jasmine",
    "//:node_modules/karma-jasmine-html-reporter",
    "//:node_modules/karma-coverage",
]
TEST_DEPS = LIBRARY_DEPS + [
    "//:node_modules/@angular/compiler",
    "//:node_modules/@angular/platform-browser",
    "//:node_modules/@angular/platform-browser-dynamic",
    "//:node_modules/jasmine-core",
    "//:node_modules/zone.js",
]

NG_DEV_DEFINE = {
    "process.env.NODE_ENV": "'development'",
    "ngJitMode": "false",
}
NG_PROD_DEFINE = {
    "process.env.NODE_ENV": "'production'",
    "ngDevMode": "false",
    "ngJitMode": "false",
}

APPLICATION_HTML_ASSETS = ["styles.scss", "favicon.ico"]

def ng_application(name, deps = [], test_deps = [], assets = None, html_assets = APPLICATION_HTML_ASSETS, visibility = ["//visibility:public"], **kwargs):
    """
    Bazel macro for compiling an Angular application. Creates {name}, test, serve targets.

    Projects structure:
      main.ts
      index.html
      styles.css, favicon.ico (defaults, can be overriden)
      src/
        **/*.{ts,css,html}

    Tests:
      src/
        **/*.spec.ts

    Args:
      name: the rule name
      deps: direct dependencies of the application
      test_deps: additional dependencies for tests
      html_assets: assets to insert into the index.html, [styles.css, favicon.ico] by default
      assets: assets to include in the file bundle
      visibility: visibility of the primary targets ({name}, 'test', 'serve')
      **kwargs: extra args passed to main Angular CLI rules
    """
    assets = assets if assets else []
    html_assets = html_assets if html_assets else []

    test_spec_srcs = native.glob(["src/**/*.spec.ts"])

    srcs = native.glob(
        ["src/main.ts", "package.json", "src/app/**/*"],
        exclude = test_spec_srcs,
    )

    # Primary app source
    ng_project(
        name = "_another_try_app",
        srcs = srcs,
        deps = deps + APPLICATION_DEPS,
        visibility = ["//visibility:private"],
    )

    _pkg_web(
        name = "prod_another_try_app",
        entry_point = "src/main.ts",
        entry_deps = [":_another_try_app"],
        html_assets = html_assets,
        assets = assets,
        production = True,
        visibility = ["//visibility:private"],
    )

    _pkg_web(
        name = "dev_another_try_app",
        entry_point = "src/main.ts",
        entry_deps = [":_another_try_app"],
        html_assets = html_assets,
        assets = assets,
        production = False,
        visibility = ["//visibility:private"],
    )

    # The default target: the prod package
    native.alias(
        name = name,
        actual = "prod_another_try_app",
        visibility = visibility,
    )

def _pkg_web(name, entry_point, entry_deps, html_assets, assets, production, visibility):
    """ Bundle and create runnable web package.

      For a given application entry_point, assets and defined constants... generate
      a bundle using that entry and constants, an index.html referencing the bundle and
      providated assets, package all content into a resulting directory of the given name.
    """

    bundle = "bundle-%s" % name

    ng_esbuild(
        name = bundle,
        entry_points = [entry_point],
        srcs = entry_deps,
        define = NG_PROD_DEFINE if production else NG_DEV_DEFINE,
        format = "esm",
        output_dir = True,
        splitting = True,
        metafile = False,
        minify = production,
        visibility = ["//visibility:private"],
    )

    html_out = "_%s_html" % name


    copy_to_directory(
        name = name,
        srcs =  html_assets + assets,
        root_paths = [".", "%s/%s" % (native.package_name(), html_out)],
        visibility = visibility,
    )

    # http server serving the bundle

def ng_pkg(name, srcs, deps = [], test_deps = [], visibility = ["//visibility:public"]):
    """
    Bazel macro for compiling an npm-like Angular package project. Creates '{name}' and 'test' targets.

    Projects structure:
      src/
        public-api.ts
        **/*.{ts,css,html}

    Tests:
      src/
        **/*.spec.ts

    Args:
      name: the rule name
      srcs: source files
      deps: package dependencies
      test_deps: additional dependencies for tests
      visibility: visibility of the primary targets ('{name}', 'test')
    """

    test_spec_srcs = native.glob(["src/**/*.spec.ts"])

    # An index file to allow direct imports of the directory similar to a package.json "main"
    write_file(
        name = "_index",
        out = "index.ts",
        content = ["export * from \"./src/public-api\";"],
        visibility = ["//visibility:private"],
    )

    ng_project(
        name = "_lib",
        srcs = srcs + [":_index"],
        deps = deps + LIBRARY_DEPS + LIBRARY_CONFIG,
        visibility = ["//visibility:private"],
    )

    npm_package(
        name = name,
        srcs = ["package.json", ":_lib"],
        # This is a perf improvement; the default will be flipped to False in rules_js 2.0
        include_runfiles = False,
        visibility = ["//visibility:public"],
    )

