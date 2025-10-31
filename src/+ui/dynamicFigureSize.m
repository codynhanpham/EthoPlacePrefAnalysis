function [w, h] = dynamicFigureSize(aspectRatio, extendHeight, scaleFactor)
    %%DYNAMICFIGURESIZE Compute an optimal figure size for video/aspect-ratio display.
    %   [W,H] = graphics.dynamicFigureSize(aspectRatio, extendHeight, scaleFactor)
    %   returns the figure width W and height H in pixels based on the screen
    %   size and video aspect ratio, applying the following rules:
    %
    %   - If both screen and video are landscape, limit video height to 70% of screen height
    %   - If both are portrait, limit video width to 80% of screen width
    %   - If screen is landscape but video is portrait, limit video height to 90% of screen height
    %   - If screen is portrait and video is landscape, limit video width to 90% of screen width
    %
    %   Then add extendHeight (can be negative) to the figure height to account
    %   for controls or other UI elements. Next, apply scaleFactor to the size
    %   before finally ensuring the figure fits within the screen by scaling
    %   down uniformly if necessary.
    %
    %   Inputs:
    %     aspectRatio  - numeric scalar, video width/height ratio
    %     extendHeight - integer, added to the final figure height (can be negative)
    %     scaleFactor  - numeric scalar > 0, scales the computed size before final fit
    %
    %   Outputs:
    %     w - figure width in pixels
    %     h - figure height in pixels (includes extendHeight)

    arguments
        aspectRatio (1,1) double {mustBeFinite, mustBePositive}
        extendHeight (1,1) double = 0
        scaleFactor (1,1) double {mustBeFinite, mustBePositive} = 1
    end

    % Screen size [left, bottom, width, height]
    scr = get(0, 'ScreenSize');
    scrW = scr(3) - 100; % leave some margin for OS elements (idk, sidebars, etc)
    scrH = scr(4) - 100; % leave some margin for titlebar + taskbar

    % Orientation flags
    screenIsLandscape = scrW >= scrH;
    videoIsLandscape  = aspectRatio >= 1; % treat square as landscape

    % Base limits per rules (percentages of screen size)
    limitHeightBothLandscape = 0.70; % 70% of screen height
    limitWidthBothPortrait   = 0.80; % 80% of screen width
    limitHeightScrLandVidPor = 0.90; % 90% of screen height
    limitWidthScrPorVidLand  = 0.90; % 90% of screen width

    % Compute video content size (before extendHeight)
    if screenIsLandscape && videoIsLandscape
        vidH = scrH * limitHeightBothLandscape;
        vidW = vidH * aspectRatio;
    elseif (~screenIsLandscape) && (~videoIsLandscape)
        vidW = scrW * limitWidthBothPortrait;
        vidH = vidW / aspectRatio;
    elseif screenIsLandscape && (~videoIsLandscape)
        vidH = scrH * limitHeightScrLandVidPor;
        vidW = vidH * aspectRatio;
    else % screen portrait, video landscape
        vidW = scrW * limitWidthScrPorVidLand;
        vidH = vidW / aspectRatio;
    end

    % Apply user scale factor to the video content size
    vidW = vidW * scaleFactor;
    vidH = vidH * scaleFactor;

    % Compose figure size with extra control height
    figW = vidW;
    figH = vidH + extendHeight; % allow extendHeight to be negative

    % Final fit: ensure the figure fits on screen; scale down uniformly if needed
    scaleDown = min([1, scrW / figW, scrH / figH]);
    figW = figW * scaleDown;
    figH = figH * scaleDown;

    % Round to integer pixels, and clamp to minimum sensible size
    figW = max(100, round(figW));
    figH = max(100, round(figH));

    w = figW;
    h = figH;
end
