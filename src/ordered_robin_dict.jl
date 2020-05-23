using DataStructures: RobinDict;

import Base: setindex!, sizehint!, empty!, isempty, length, copy, empty,
             getindex, getkey, haskey, iterate, @propagate_inbounds,
             pop!, delete!, get, get!, isbitstype, in, hashindex, isbitsunion,
             isiterable, dict_with_eltype, KeySet, Callable, _tablesz, filter!

mutable struct OrderedRobinDict{K,V} <: AbstractDict{K,V}
    dict::RobinDict{K, Int32} 
    keys::Vector{K}
    vals::Vector{V}
    count::Int32

    function OrderedRobinDict{K, V}() where {K, V}
        new{K, V}(RobinDict{K, Int32}(), Vector{K}(), Vector{V}(), 0)
    end

    function OrderedRobinDict{K, V}(d::OrderedRobinDict{K, V}) where {K, V}
        new{K, V}(copy(d.dict), copy(d.keys), copy(d.vals), d.count)
    end

    function OrderedRobinDict{K,V}(kv) where {K, V}
        h = OrderedRobinDict{K,V}()
        for (k,v) in kv
            h[k] = v
        end
        return h
    end
    OrderedRobinDict{K,V}(p::Pair) where {K,V} = setindex!(OrderedRobinDict{K,V}(), p.second, p.first)
    function OrderedRobinDict{K,V}(ps::Pair...) where V where K
        h = OrderedRobinDict{K,V}()
        # sizehint!(h, length(ps))
        for p in ps
            h[p.first] = p.second
        end
        return h
    end
end

OrderedRobinDict() = OrderedRobinDict{Any,Any}()
OrderedRobinDict(kv::Tuple{}) = OrderedRobinDict()
copy(d::OrderedRobinDict) = OrderedRobinDict(d)
empty(d::OrderedRobinDict, ::Type{K}, ::Type{V}) where {K, V} = OrderedRobinDict{K, V}()

OrderedRobinDict(ps::Pair{K,V}...) where {K,V} = OrderedRobinDict{K,V}(ps)
OrderedRobinDict(ps::Pair...)                  = OrderedRobinDict(ps)

OrderedRobinDict(d::AbstractDict{K, V}) where {K, V} = OrderedRobinDict{K, V}(d)

function OrderedRobinDict(kv)
    try
        return dict_with_eltype((K, V) -> OrderedRobinDict{K, V}, kv, eltype(kv))
    catch e
        if !isiterable(typeof(kv)) || !all(x -> isa(x, Union{Tuple,Pair}), kv)
            !all(x->isa(x,Union{Tuple,Pair}),kv)
            throw(ArgumentError("OrderedRobinDict(kv): kv needs to be an iterator of tuples or pairs"))
        else
            rethrow(e)
        end
    end
end

length(d::OrderedRobinDict) = d.count
isempty(d::OrderedRobinDict) = (length(d) == 0)

function empty!(h::OrderedRobinDict{K,V}) where {K, V}
    empty!(h.dict)
    empty!(h.keys)
    empty!(h.vals)
    h.count = 0
    return h
end

function _setindex!(h::OrderedRobinDict, v, key)
    hk, hv = h.keys, h.vals
    ccall(:jl_array_grow_end, Cvoid, (Any, UInt), hk, 1)
    nk = length(hk)
    @inbounds hk[nk] = key
    ccall(:jl_array_grow_end, Cvoid, (Any, UInt), hv, 1)
    @inbounds hv[nk] = v
    @inbounds h.dict[key] = Int32(nk)
    h.count += 1
end

function setindex!(h::OrderedRobinDict{K, V}, v0, key0) where {K,V}
    key = convert(K,key0)
    if !isequal(key,key0)
        throw(ArgumentError("$key0 is not a valid key for type $K"))
    end
    v = convert(V,  v0)

    index = get(h.dict, key, -2)

    if index < 0
        _setindex!(h, v0, key0)
    else
        @assert haskey(h, key0)
        @inbounds orig_v = h.vals[index]
        (orig_v != v0) && (@inbounds h.vals[index] = v0)
    end

    check_for_rehash(h) && rehash!(h)

    return h
end

check_for_rehash(h) = false

function rehash!(h::OrderedRobinDict)
    return h
end

function get!(h::OrderedRobinDict{K,V}, key0, default) where {K,V}
    key = convert(K,key0)
    if !isequal(key,key0)
        throw(ArgumentError("$key0 is not a valid key for type $K"))
    end

    index = get(h.dict, key, -2)

    index > 0 && return h.vals[index]

    v = convert(V,  default)
    setindex!(h, v, key)
    return v
end

function get!(default::Base.Callable, h::OrderedRobinDict{K,V}, key0) where {K,V}
    key = convert(K,key0)
    if !isequal(key,key0)
        throw(ArgumentError("$key0 is not a valid key for type $K"))
    end

    index = get(h.dict, key, -2)

    index > 0 && return h.vals[index]

    v = convert(V,  default())

    if index > 0
        h.keys[index] = key
        h.vals[index] = v
    else
        setindex!(h, v, key)
    end
    return v
end

function getindex(h::OrderedRobinDict{K,V}, key) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? throw(KeyError(key)) : h.vals[index]::V
end

function get(h::OrderedRobinDict{K,V}, key, default) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? default : h.vals[index]::V
end

function get(default::Base.Callable, h::OrderedRobinDict{K,V}, key) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? default() : h.vals[index]::V
end

haskey(h::OrderedRobinDict, key) = (get(h.dict, key, -2) > 0)
in(key, v::Base.KeySet{K,T}) where {K,T<:OrderedRobinDict{K}} = (get(h.dict, key, -1) >= 0)

function getkey(h::OrderedRobinDict{K,V}, key, default) where {K,V}
    index = get(h.dict, key, -1)
    return (index < 0) ? default : h.keys[index]::K
end

@propagate_inbounds isslotfilled(h::OrderedRobinDict, index) = (h.dict[h.keys[index]] == index)

function _pop!(h::OrderedRobinDict, index)
    @inbounds val = h.vals[index]
    _delete!(h, index)
    return val
end

function pop!(h::OrderedRobinDict)
    check_for_rehash(h) && rehash!(h)
    index = length(h.keys)
    @inbounds while (index > 0)
        isslotfilled(h, index) && break
        index -= 1
    end
    index == 0 && rehash!(h)
    @inbounds key = h.keys[index]
    return key => _pop!(h, index)
end

function pop!(h::OrderedRobinDict, key)
    index = get(h, key, -1)
    isslotfilled(h, index) ? _pop!(h, index) : throw(KeyError(key))
end

function pop!(h::OrderedRobinDict, key, default)
    index = get(h, key, -1)
    isslotfilled(h, index) ? _pop(h, index) : default
end

function _delete!(h::OrderedRobinDict, index)
    @inbounds h.dict[h.keys[index]] = -1
    h.count -= 1
    check_for_rehash(h) ? rehash!(h) : h
end

function get_first_filled_index(h::OrderedRobinDict)
    index = 1
    while (true)
        isslotfilled(h, index) && return index
        index += 1
    end
end

function get_next_filled_index(h::OrderedRobinDict, index)
    # get the next filled slot, including index and beyond
    while (index <= length(h.keys))
        isslotfilled(h, index) && return index
        index += 1
    end
    return -1
end

function iterate(h::OrderedRobinDict)
    isempty(h) && return nothing
    check_for_rehash(h) && rehash!(h)
    index = get_first_filled_index(h)
    return (Pair(h.keys[index], h.vals[index]), index+1)
end

function iterate(h::OrderedRobinDict, i)
    length(h.keys) < i && return nothing
    index = get_next_filled_index(h, i) 
    (index < 0) && return nothing
    return (Pair(h.keys[index], h.vals[index]), index+1)
end