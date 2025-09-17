function argout = allargout(func, varargin, kvargs)
    %%ALLARGOUT This wrapper function calls the input functions
    % and returns all output arguments as a cell array.
    arguments
        func (1,1) function_handle
    end

    arguments (Repeating)
        varargin
    end

    arguments
        kvargs.NumOutput (1,1) double {mustBeInteger} = -1
    end

    nout = nargout(func);
    if nout < 0 && kvargs.NumOutput < 0
        error('Function %s has variable number of output arguments. Please specify the number of outputs explicitly with ''NumOutput''', func2str(func));
    end

    if kvargs.NumOutput > 0
        nout = kvargs.NumOutput;
    else
        nout = max(nout, 0); % Ensure non-negative
    end

    if nout == 0
        func(varargin{:});
        argout = {};
    else
        [argout{1:nout}] = func(varargin{:});
    end
end