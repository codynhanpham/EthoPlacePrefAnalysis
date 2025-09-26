function hsl = rgb2hsl(rgb)
    %%RGB2HSL Convert normalized RGB color values to HSL color values
    %
    %   hsl = rgb2hsl(rgb)
    %
    %   Inputs:
    %       rgb - Any color specification that can be parsed with validatecolor()
    %
    %   Outputs:
    %       hsl - An Nx3 matrix of HSL color values where:
    %             H (Hue) is in range [0, 360] degrees
    %             S (Saturation) is in range [0, 100] percent
    %             L (Lightness) is in range [0, 100] percent
    %
    %   See also: utils.color.hsl2rgb, validatecolor

    arguments
        rgb {validatecolor(rgb, "multiple")}
    end

    rgb = validatecolor(rgb, "multiple"); % Ensure rgb is in Nx3 format
    
    r = rgb(:,1);
    g = rgb(:,2);
    b = rgb(:,3);
    
    % Find min and max values for each row
    minRGB = min(rgb, [], 2);
    maxRGB = max(rgb, [], 2);
    delta = maxRGB - minRGB;
    
    % Calculate Lightness
    L = (maxRGB + minRGB) / 2;
    
    % Initialize HSL matrix
    hsl = zeros(size(rgb));
    
    % Calculate Saturation
    S = zeros(size(L));
    nonZeroDelta = delta > 0;
    
    % For non-zero delta values
    lightCondition = L(nonZeroDelta) <= 0.5;
    S(nonZeroDelta & lightCondition) = delta(nonZeroDelta & lightCondition) ./ ...
        (maxRGB(nonZeroDelta & lightCondition) + minRGB(nonZeroDelta & lightCondition));
    S(nonZeroDelta & ~lightCondition) = delta(nonZeroDelta & ~lightCondition) ./ ...
        (2 - maxRGB(nonZeroDelta & ~lightCondition) - minRGB(nonZeroDelta & ~lightCondition));
    
    % Calculate Hue
    H = zeros(size(L));
    
    % Red is maximum
    redMax = (maxRGB == r) & nonZeroDelta;
    H(redMax) = mod((g(redMax) - b(redMax)) ./ delta(redMax), 6);
    
    % Green is maximum
    greenMax = (maxRGB == g) & nonZeroDelta;
    H(greenMax) = (b(greenMax) - r(greenMax)) ./ delta(greenMax) + 2;
    
    % Blue is maximum
    blueMax = (maxRGB == b) & nonZeroDelta;
    H(blueMax) = (r(blueMax) - g(blueMax)) ./ delta(blueMax) + 4;
    
    % Convert hue to [0,360] range (degrees)
    H = H * 60;
    
    % Convert saturation and lightness to [0,100] range (percentages)
    S = S * 100;
    L = L * 100;
    
    % Assemble HSL matrix
    hsl(:,1) = H;
    hsl(:,2) = S;
    hsl(:,3) = L;
end