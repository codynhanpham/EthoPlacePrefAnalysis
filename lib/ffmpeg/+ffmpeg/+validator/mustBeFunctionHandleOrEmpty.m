function mustBeFunctionHandleOrEmpty(x)
    if ~isempty(x) && ~isa(x, 'function_handle') && ~isscalar(x)
        error('Value must be a scalar function_handle or empty.');
    end
end