function normalizedRGB = fromRGB(rgb)
    %%fromRGB Convert RGB values in the range [0, 255] to normalized [0, 1] for MATLAB
    %
    %   normalizedRGB = fromRGB(rgb)
    %
    %   Inputs:
    %       rgb - An Nx3 matrix of RGB color values in the range [0, 255]
    %
    %   Outputs:
    %       normalizedRGB - An Nx3 matrix of RGB color values in the range [0, 1]

    arguments
        rgb (:,3) double {mustBeNonnegative, mustBeInteger, mustBeInRange(rgb, 0, 255)}
    end

    normalizedRGB = double(rgb) / 255;
end