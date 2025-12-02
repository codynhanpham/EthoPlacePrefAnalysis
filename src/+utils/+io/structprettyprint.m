function str = structprettyprint(s, indent, maxArrayElements)
    %STRUCTPRETTYPRINT Create a formatted string representation of a structure
    %
    %   str = structprettyprint(s)
    %   str = structprettyprint(s, indent)
    %   str = structprettyprint(s, indent, maxArrayElements)
    %
    %   Inputs:
    %       - s: the structure to print (can be struct array)
    %       - indent: the indentation size to use (default: 2)
    %       - maxArrayElements: maximum number of array elements to display (default: 3)
    %
    %   Outputs:
    %       - str: the formatted string representation of the structure
    %
    %   ---
    %
    %   Example:
    %       s = struct('name', 'Bob', 'age', 30, 'height', 1.8);
    %       str = structprettyprint(s, 4, Inf); % Indent by 4 spaces, show all array elements
    %       disp(str);
    %

    arguments
        s struct
        indent (1,1) double {mustBeInteger, mustBeNonnegative} = 2
        maxArrayElements (1,1) double = 3
    end

    str = prep__structprettyprint(s, indent, maxArrayElements);
    str = strjoin(string(str), newline);
end


function str = prep__structprettyprint(s, indent, maxArrayElements)
    %Recursively load and format the fields of a single structure
    
    arguments
        s struct
        indent (1,1) double {mustBeInteger, mustBeNonnegative} = 2
        maxArrayElements (1,1) double = 3
    end
    
    % Handle struct arrays
    if numel(s) > 1        
        str = {};
        sizeArray = size(s);
        sizeStr = sprintf('%dx', sizeArray);
        sizeStr = sizeStr(1:end-1); % Remove trailing 'x'
        str{end+1} = sprintf('Struct Array [%s]:', sizeStr);

        % Process each struct in the array
        for idx = 1:min(numel(s), maxArrayElements)
            arrayIndentStr = repmat(' ', 1, indent);
            elementHeader = sprintf('%sElement(%d):', arrayIndentStr, idx);
            str{end+1} = elementHeader; %#ok<*AGROW>
            
            % Get the formatted representation of this struct element - use parent indent
            elementStr = prep__structprettyprint(s(idx), indent + indent, maxArrayElements);
            
            % Add each line with additional indentation
            for j = 1:length(elementStr)
                str{end+1} = [arrayIndentStr elementStr{j}];
            end
            
            % Add separator between elements (except for the last one)
            if idx < min(numel(s), maxArrayElements)
                str{end+1} = '';
            end
        end
        
        % Add ellipsis if there are more elements
        if numel(s) > maxArrayElements
            str{end+1} = [repmat(' ', 1, indent) '...'];
        end
        
        return;
    end

    % Process a single structure
    fieldNames = fieldnames(s);
    str = {};
    
    % Indentation strings
    indentStr = repmat(' ', 1, indent);
    baseIndent = repmat(' ', 1, 0); % Adjusted to use indent parameter

    % Add opening brace
    str{end+1} = '{';

    % Process each field
    for i = 1:length(fieldNames)
        fieldName = fieldNames{i};
        fieldValue = s.(fieldName);
        
        % Field name prefix
        fieldPrefix = [indentStr fieldName ': '];
        
        % Process field value based on its type
        if isstruct(fieldValue)
            if isscalar(fieldValue)
                % Single structure - get recursive representation - use parent indent
                nestedStr = prep__structprettyprint(fieldValue, indent, maxArrayElements);
                
                % First line combines field name with opening brace
                str{end+1} = [fieldPrefix nestedStr{1}];
                
                % Apply correct indentation to remaining lines
                for j = 2:length(nestedStr)
                    str{end+1} = [indentStr nestedStr{j}];
                end
            else
                % Array of structures
                str{end+1} = [fieldPrefix 'Array of ' num2str(numel(fieldValue)) ' structures'];
                elemIndent = repmat(' ', 1, indent * 2); % Use indent parameter
                
                for k = 1:min(numel(fieldValue), maxArrayElements)
                    str{end+1} = [elemIndent sprintf('Element(%d):', k)];
                    
                    % Get recursive representation - use parent indent
                    elemStr = prep__structprettyprint(fieldValue(k), indent, maxArrayElements);
                    
                    % Apply element indentation to all lines
                    for j = 1:length(elemStr)
                        str{end+1} = [elemIndent elemStr{j}];
                    end
                    
                    if k < min(numel(fieldValue), maxArrayElements)
                        str{end+1} = '';
                    end
                end
                
                if numel(fieldValue) > maxArrayElements
                    str{end+1} = [elemIndent '...'];
                end
            end
        elseif isnumeric(fieldValue) || islogical(fieldValue)
            % Format numeric or logical values
            if isscalar(fieldValue)
                str{end+1} = [fieldPrefix num2str(fieldValue)];
            elseif isempty(fieldValue)
                str{end+1} = [fieldPrefix '[]'];
            else
                sizeStr = sprintf('%dx', size(fieldValue));
                sizeStr = sizeStr(1:end-1); % Remove trailing 'x'
                str{end+1} = [fieldPrefix '[' sizeStr ' ' class(fieldValue) ']'];
            end
        elseif ischar(fieldValue)
            % Format character array
            if size(fieldValue, 1) == 1
                str{end+1} = [fieldPrefix '''' fieldValue ''''];
            else
                str{end+1} = [fieldPrefix '[' num2str(size(fieldValue, 1)) 'x' num2str(size(fieldValue, 2)) ' char]'];
            end
        elseif iscell(fieldValue)
            % Format cell array
            cellSizeStr = sprintf('%dx', size(fieldValue));
            cellSizeStr = cellSizeStr(1:end-1);
            str{end+1} = [fieldPrefix '{' cellSizeStr ' cell}'];
        elseif isstring(fieldValue)
            % Format string array
            if isscalar(fieldValue)
                str{end+1} = [fieldPrefix '"' char(fieldValue) '"'];
            else
                stringSizeStr = sprintf('%dx', size(fieldValue));
                stringSizeStr = stringSizeStr(1:end-1);
                str{end+1} = [fieldPrefix '[' stringSizeStr ' string]'];
            end
        else
            % Other types
            str{end+1} = [fieldPrefix class(fieldValue)];
        end
        
        % Add comma for all but the last field
        if i < length(fieldNames)
            str{end} = [str{end} ','];
        end
    end

    % Add closing brace with proper indentation
    str{end+1} = [baseIndent '}'];
end