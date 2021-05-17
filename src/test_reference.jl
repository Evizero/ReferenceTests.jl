"""
    @test_reference filename expr [by] [kw...]

Tests that the expression `expr` with reference `filename` using
equality test strategy `by`.

The pipeline of `test_reference` is:

1. preprocess `expr`
2. read and preprocess `filename`
3. compare the results using `by`
4. if test fails in an interactive session (e.g, `include(test/runtests.jl)`), an interactive dialog will be trigered.

Arguments:

* `filename::String`: _relative_ path to the file that contains the macro invocation.
* `expr`: the actual content used to compare.
* `by`: the equality test function. By default it is `isequal` if not explicitly stated.
* `force_raw_txt`: Force reading the file as a raw string

# Types

The file-extension of `filename`, as well as the type of the
result of evaluating `expr`, determine how contents are processed and
compared. The contents is treated as:

* Images when `expr` is an image type, i.e., `AbstractArray{<:Colorant}`;
* SHA256 when `filename` endswith `*.sha256`;
* Text as a fallback.

## Images

Images are compared _approximately_ using a different `by` to ignore most encoding
and decoding errors. The default function is generated from [`psnr_equality`](@ref).

The file can be either common image files (e.g., `*.png`), which are handled by
`FileIO`, or text-coded `*.txt` files, which is handled by `ImageInTerminal`.
Text-coded image has less storage requirements and also allows to view the
reference file in a simple terminal using `cat`.

## SHA256

The hash of the `expr` and content of `filename` are compared.

!!! tip

    This is useful for a convenient low-storage way of making
    sure that the return value doesn't change for selected test
    cases.

## Fallback

Simply test the equality of `expr` and the contents of `filename` without any
preprocessing.

# Examples

```julia
# store as string using ImageInTerminal with encoding size (5,10)
@test_reference "camera.txt" testimage("cameraman") size=(5,10)

# using folders in the relative path is allowed
@test_reference "references/camera.png" testimage("cameraman")

# Images can also be stored as hash. Note however that this
# can only check for equality (no tolerance possible)
@test_reference "references/camera.sha256" testimage("cameraman")

# test images with custom psnr threshold
@test_reference "references/camera.png" testimage("cameraman") by=psnr_equality(20)

# test number with absolute tolerance 10
@test_reference "references/string3.txt" 1338 by=(ref, x)->isapprox(ref, x; atol=10)
```
"""
macro test_reference(reference, actual, kws...)
    dir = Base.source_dir()
    expr = :(test_reference(abspath(joinpath($dir, $(esc(reference)))), $(esc(actual))))
    for kw in kws
        (kw isa Expr && kw.head == :(=)) || error("invalid signature for @test_reference")
        k, v = kw.args
        push!(expr.args, Expr(:kw, k, esc(v)))
    end
    expr
end

function test_reference(
    filename::AbstractString, raw_actual;
    by = nothing, render = nothing, force_raw_txt = false, kw...)

    test_reference(query_extended(filename, force_raw_txt), raw_actual, by, render; kw...)
end

function test_reference(
    reference_file::File{F},
    raw_actual::T,
    equiv=nothing,
    rendermode=nothing;
    kw...) where {F <: DataFormat, T}

    reference_path = reference_file.filename
    reference_dir, reference_filename = splitdir(reference_path)

    actual = _convert(F, raw_actual; kw...)

    # infer the default rendermode here
    # since `nothing` is always passed to this method from
    # test_reference(filename::AbstractString, raw_actual; kw...)
    if rendermode === nothing
        rendermode = default_rendermode(F, actual)
    end

    if !isfile(reference_path)  # when reference file doesn't exists
        mkpath(reference_dir)
        savefile(reference_file, actual)
        @info(
            "Reference file for \"$reference_filename\" did not exist. It has been created",
            new_reference=reference_path,
        )

        # TODO: move encoding out from render
        render(rendermode, actual)

        @info("Please run the tests again for any changes to take effect")
        return nothing # skip current test case
    end

    # file exists
    reference = loadfile(typeof(actual), reference_file)

    if equiv === nothing
        # generally, `reference` and `actual` are of the same type after preprocessing
        equiv = default_equality(reference, actual)
    end

    if equiv(reference, actual)
        @test true # to increase test counter if reached
    else  # When test fails
        # Saving actual file so user can look at it
        actual_path = joinpath(mismatch_staging_dir(), reference_filename)
        actual_file = typeof(reference_file)(actual_path)
        savefile(actual_file, actual)

        # Report to user.
        @info(
            "Reference Test for \"$reference_filename\" failed.",
            reference=reference_path,
            actual=actual_path,
        )
        render(rendermode, reference, actual)

        if !isinteractive()
            error("You need to run the tests interactively with 'include(\"test/runtests.jl\")' to update reference images")
        end

        if !input_bool("Replace reference with actual result?")
            @test false
        else
            mv(actual_path, reference_path; force=true)  # overwrite old file it
            @info("Please run the tests again for any changes to take effect")
        end
    end
end

"""
    mismatch_staging_dir()

The directory where we store files that don't match so user can look at them.
If the enviroment variable `REFERENCE_TESTS_STAGING_PATH` is set then we will use that directory.
If not a temporary directory will be created. Note that this temporary directory will not be
deleted when julia exists. Since in that case the files would may be deleted before you can
look at them. You should use your operating systems standard mechanisms to clean up excess
temporary directories.
"""
function mismatch_staging_dir()
    return mkpath(expanduser(get(ENV,
        "REFERENCE_TESTS_STAGING_PATH",
        VERSION >= v"1.3" ? mktempdir(; cleanup=false) : mktempdir()
    )))
end
