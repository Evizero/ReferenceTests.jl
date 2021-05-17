#######################################
# IO
# Right now this basically just extends FileIO to support some things as text files

const TextFile = Union{File{format"TXT"}, File{format"SHA256"}}

function loadfile(::Type{T}, file::File) where T
    T(load(file))::T # Fallback to FileIO
end

function loadfile(::Type{T}, file::TextFile) where T  # specialize on T only to prevent ambiguity
    replace(read(file.filename, String), "\r"=>"") # ignore CRLF/LF difference
end

function loadfile(::Type{<:Number}, file::File{format"TXT"})
    parse(Float64, loadfile(String, file))
end

function savefile(file::File, content)
    save(file, content) # Fallback to FileIO
end

function savefile(file::TextFile, content)
    write(file.filename, string(content))
end

function query_extended(filename, force_raw_txt = false)
    force_raw_txt && return File{format"TXT"}(filename)
    file, ext = splitext(filename)
    # TODO: make this less hacky
    if uppercase(ext) == ".SHA256"
        res = File{format"SHA256"}(filename)
    else
        res = query(filename)
        if res isa File{DataFormat{:UNKNOWN}}
            res = File{format"TXT"}(filename)
        end
    end
    res
end

"""
    _convert(T::Type{<:DataFormat}, x; kw...) -> out

Convert `x` to a validate content for file data format `T`.
"""
_convert(::Type{<:DataFormat}, x; kw...) = x

# plain TXT
_convert(::Type{DataFormat{:TXT}}, x; kw...) = replace(string(x), "\r"=>"") # ignore CRLF/LF difference
_convert(::Type{DataFormat{:TXT}}, x::Number; kw...) = x
function _convert(::Type{DataFormat{:TXT}}, x::AbstractArray{<:AbstractString}; kw...)
    return join(x, '\n')
end
function _convert(
    ::Type{DataFormat{:TXT}}, img::AbstractArray{<:Colorant};
    size = (20,40), kw...)

    # encode image into string
    strs = @withcolor ImageInTerminal.encodeimg(
        ImageInTerminal.SmallBlocks(),
        ImageInTerminal.TermColor256(),
        img,
        size...)[1]
    return join(strs,'\n')
end

# PNG  (Including images as arrays of colorants, and things like Plots.jl plots etc)
function _convert(::Type{<:DataFormat{:PNG}}, data)::AbstractArray{<:Colorant}
    mktempdir() do dir
        filename = File{DataFormat{:PNG}}(joinpath(dir, "inconversion.png"))
        savefile(filename, data)
        load(filename)
    end
end
_convert(::Type{<:DataFormat{:PNG}}, img::AbstractArray{<:Colorant}; kw...) = img

# SHA256
_convert(::Type{DataFormat{:SHA256}}, x; kw...) = bytes2hex(sha256(string(x)))
function _convert(::Type{DataFormat{:SHA256}}, img::AbstractArray{<:Colorant}; kw...)
    # encode image into SHA256
    size_str = bytes2hex(sha256(reinterpret(UInt8,[map(Int64,size(img))...])))
    img_str = bytes2hex(sha256(reinterpret(UInt8,vec(rawview(channelview(img))))))

    return size_str * img_str
end
