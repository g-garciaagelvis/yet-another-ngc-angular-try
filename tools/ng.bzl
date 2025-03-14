load("@aspect_rules_esbuild//esbuild:defs.bzl", "esbuild")
load("@aspect_rules_ts//ts:defs.bzl", "ts_config","ts_project")

def ng_project(name, **kwargs):
    """The rules_js ts_project() configured with the Angular ngc compiler.
    """
    ts_project(
        name = name,
        # Compiler
        tsc = "//tools:ngc",
        supports_workers = False,
        tsconfig = "//:tsconfig",
        declaration =  True,
        declaration_map = True,
        source_map = True,
        transpiler = "tsc",
        **kwargs
    )

def ng_esbuild(name, **kwargs):
    """The rules_esbuild esbuild() configured with the Angular linker configuration
    """

    esbuild(
        name = name,
        **kwargs
    )
