function arr = nestedChildren(obj, kvargs)
    %%NESTEDCHILDREN Get all nested children of a given object
    %
    %   Inputs:
    %       obj - The parent object
    %
    %   Name-Value Pair Arguments:
    %       'MaxDepth' - The maximum depth of recursion (default: Inf)
    %       'Type' - The type of child objects to retrieve (default: 'all')
    %
    %   Outputs:
    %       arr - An array of nested child objects
    arguments
        obj
        kvargs.MaxDepth (1,1) double {mustBePositive} = Inf
        kvargs.Type {mustBeTextScalarOrEmpty} = ''
    end

    kvargs.MaxDepth = round(kvargs.MaxDepth);
    if kvargs.MaxDepth < 1
        arr = [];
        return;
    end

    % Initialize the result array
    arr = [];
    
    % Check if the object has a Children property
    if ~isprop(obj, 'Children') && ~isfield(obj, 'Children')
        return;
    end
    
    % Get direct children
    try
        if isprop(obj, 'Children')
            children = obj.Children;
        elseif isfield(obj, 'Children')
            children = obj.Children;
        else
            return;
        end
    catch
        return;
    end
    
    % If no children, return empty
    if isempty(children)
        return;
    end
    
    % Filter children by type if specified
    if ~isempty(kvargs.Type)
        validChildren = [];
        for i = 1:length(children)
            if isa(children(i), kvargs.Type)
                validChildren = [validChildren; children(i)]; %#ok<AGROW>
            end
        end
        children = validChildren;
    end
    
    % Add direct children to result
    arr = [arr; children(:)];
    
    % Recursively get nested children if max depth allows
    if kvargs.MaxDepth > 1
        for i = 1:length(children)
            nestedArr = utils.nestedChildren(children(i), ...
                'MaxDepth', kvargs.MaxDepth - 1, ...
                'Type', kvargs.Type);
            arr = [arr; nestedArr(:)]; %#ok<AGROW>
        end
    end
    
end


function mustBeTextScalarOrEmpty(x)
    if isempty(x)
        return;
    end
    mustBeTextScalar(x);
end