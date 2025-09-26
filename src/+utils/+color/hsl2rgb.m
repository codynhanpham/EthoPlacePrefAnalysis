function rgb = hsl2rgb(hsl)
    %%HSL2RGB Convert HSL color values to normalized RGB color values
    %
    %   rgb = utils.color.hsl2rgb(hsl)
    %
    %   Input:
    %       hsl - An Nx3 matrix of HSL color values where:
    %             H (Hue) is in range [0, 360] degrees
    %             S (Saturation) is in range [0, 100] percent
    %             L (Lightness) is in range [0, 100] percent
    %
    %   Output:
    %       rgb - An Nx3 matrix of normalized RGB color values in range [0, 1]
    %
    %   See also: utils.color.rgb2hsl, validatecolor

    arguments
        hsl (:, 3) double {mustBeHSL}
    end

    % Convert input to [0,1] ranges for calculation
    H = hsl(:,1) / 360;  % Hue: [0,360] -> [0,1]
    S = hsl(:,2) / 100;  % Saturation: [0,100] -> [0,1]
    L = hsl(:,3) / 100;  % Lightness: [0,100] -> [0,1]
    
    % Initialize RGB matrix
    rgb = zeros(size(hsl));
    
    % Handle grayscale case (saturation = 0)
    grayMask = S == 0;
    rgb(grayMask, :) = repmat(L(grayMask), 1, 3);
    
    % Handle colored pixels (saturation > 0)
    colorMask = ~grayMask;
    if any(colorMask)
        H_color = H(colorMask);
        S_color = S(colorMask);
        L_color = L(colorMask);
        
        % Calculate intermediate values
        q = zeros(size(L_color));
        lightCondition = L_color < 0.5;
        q(lightCondition) = L_color(lightCondition) .* (1 + S_color(lightCondition));
        q(~lightCondition) = L_color(~lightCondition) + S_color(~lightCondition) - ...
            L_color(~lightCondition) .* S_color(~lightCondition);
        
        p = 2 * L_color - q;
        
        % Calculate RGB components
        rgb(colorMask, 1) = hue2rgb(p, q, H_color + 1/3);
        rgb(colorMask, 2) = hue2rgb(p, q, H_color);
        rgb(colorMask, 3) = hue2rgb(p, q, H_color - 1/3);
    end
end


function rgb_component = hue2rgb(p, q, t)
    % Normalize t to [0,1] range
    t = mod(t, 1);
    
    rgb_component = zeros(size(t));
    
    % Apply piecewise function
    mask1 = t < 1/6;
    rgb_component(mask1) = p(mask1) + (q(mask1) - p(mask1)) .* 6 .* t(mask1);
    
    mask2 = t >= 1/6 & t < 1/2;
    rgb_component(mask2) = q(mask2);
    
    mask3 = t >= 1/2 & t < 2/3;
    rgb_component(mask3) = p(mask3) + (q(mask3) - p(mask3)) .* (2/3 - t(mask3)) .* 6;
    
    mask4 = t >= 2/3;
    rgb_component(mask4) = p(mask4);
end


function mustBeHSL(hsl)
    arguments
        hsl (:, 3) double {mustBeNonnegative, mustBeReal, mustBeFinite}
    end

    if any(hsl(:,1) < 0 | hsl(:,1) > 360)
        error('Hue (H) values must be in the range [0, 360] degrees.');
    end
    if any(hsl(:,2) < 0 | hsl(:,2) > 100)
        error('Saturation (S) values must be in the range [0, 100] percent.');
    end
    if any(hsl(:,3) < 0 | hsl(:,3) > 100)
        error('Lightness (L) values must be in the range [0, 100] percent.');
    end
end