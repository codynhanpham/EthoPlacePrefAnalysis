%% adjustColorBrightness - Function
%
% function new_rgb = adjustColorBrightness(rgb, diffLevel)
%
% This function adjusts the brightness of an RGB color based on a
% specified level of difference between the original color and the
% color after adjustment. Useful for dynamically generating colors for hover/accent effects.
%
% Parameters:
%   rgb: The original RGB color as a 3-element vector.
%   diffLevel: The level of difference between the original color and color after adjustment. Set as value between 0 and 1. Final value will be clamped to [0-1].

function new_rgb = adjustColorBrightness(rgb, diffLevel)
    % make sure rgb is a valid color
    rgb = validatecolor(rgb);
    % Clamp diffLevel to [0-1]
    diffLevel = max(0, min(1, diffLevel));

    % Calculate the new color
    hsv = rgb2hsv(rgb);

    if hsv(3) < 0.5
        % make it lighter
        hsv(3) = hsv(3) + diffLevel;
    else
        % make it darker
        hsv(3) = hsv(3) - diffLevel;
    end

    new_rgb = hsv2rgb(hsv);
end