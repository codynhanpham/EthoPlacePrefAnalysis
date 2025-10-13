function cl_out = findAttrValue(obj,attrName,varargin)
    %%FINDATTRVALUE Find all properties with a given attribute value
    % Given an object, find all properties with a given attribute value
    %
    %   cl_out = findAttrValue(obj,attrName,attrValue)
    %
    %   Inputs:
    %       obj - Object to search
    %       attrName - Name of the attribute to search for
    %       attrValue - Value of the attribute to search for, can be omitted if attrName is a logical value
    %
    %   Outputs:
    %       cl_out - Cell array of property names
    %
    %   Example:
    %       cl_out = findAttrValue(obj,'Hidden')
    %       cl_out = findAttrValue(obj,'GetAccess','private')
    %
    %   See also: https://www.mathworks.com/help/matlab/matlab_oop/getting-information-about-properties.html

    if ischar(obj)
        mc = matlab.metadata.Class.fromName(obj);
    elseif isobject(obj)
        mc = metaclass(obj);
    end
    ii = 0; numb_props = length(mc.PropertyList);
    cl_array = cell(1,numb_props);
    for  c = 1:numb_props
        mp = mc.PropertyList(c);
        if isempty (findprop(mp,attrName))
            error('Not a valid attribute name')
        end
        attrValue = mp.(attrName);
        if attrValue
            if islogical(attrValue) || strcmp(varargin{1},attrValue)
                ii = ii + 1;
                cl_array(ii) = {mp.Name};
            end
        end
    end
    cl_out = cl_array(1:ii);
end