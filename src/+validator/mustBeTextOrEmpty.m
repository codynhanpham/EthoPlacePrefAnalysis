function mustBeTextOrEmpty(A)
    %MUSTBETEXTOREMPTY Validate that value is text or empty
    %   MUSTBETEXTOREMPTY(A) throws an error if A is not text or empty.
    
    if isempty(A)
        return;
    end
    
    mustBeText(A);
end