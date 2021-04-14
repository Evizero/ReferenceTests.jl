"""
    default_equality(reference, actual) -> f

Infer a suitable equality comparison method `f` according to input types.

`f` is a function that satisfies signature `f(reference, actual)::Bool`. If `f` outputs
`true`, it indicates that `reference` and `actual` are "equal" in the sense of `f`.
"""
default_equality(reference, actual) = isequal
function default_equality(
    reference::AbstractArray{<:Colorant},
    actual::AbstractArray{<:Colorant})

    return psnr_equality()
end

# ---------------------------------
# Image

"""
    psnr_equality(threshold=25) -> f

Generates an equality comparison function in terms of Peak Signal-to-Noise Ratio (PSNR).

The return function `f` accepts two images `reference` and `actual` as its inputs;
`f(reference, actual) == true` if `psnr(reference, actual) >= threshold`.

This function is useful for image comparison; higher PSNR means higher image similarity.
Hence if you want to loose the equality test creterion, you can use a __smaller__ threshold
value, e.g.,

```julia
@test_reference "references/camera.png" testimage("cameraman") by=psnr_equality(20)
```
"""
function psnr_equality(threshold=25)
    function (ref, x)
        if size(ref) != size(x)
            # trigger a test fail instead of throwing error
            @warn("test fails because size(ref) $(size(ref)) != size(x) $(size(x))")
            return false
        end
        rst = _psnr(ref, x)
        if rst >= threshold
            return true
        else
            @warn("test fails because PSNR $rst < $threshold")
            return false
        end
    end
end

# a simplified PSNR is sufficient since we only use it to approximately compare two images
_psnr(ref::AbstractArray{<:Color3}, x::AbstractArray{<:Color3}) =
    _psnr(channelview(RGB.(ref)), channelview(RGB.(x)), 1.0)

_psnr(ref::AbstractArray{<:AbstractGray}, x::AbstractArray{<:AbstractGray}) =
    _psnr(channelview(ref), channelview(x), 1.0)

_psnr(ref::AbstractArray{<:Real}, x::AbstractArray{<:Real}, peakval::Real) =
    20log10(peakval) - 10log10(euclidean(float.(ref), float.(x)))
