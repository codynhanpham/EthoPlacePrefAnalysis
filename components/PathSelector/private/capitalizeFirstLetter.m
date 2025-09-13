%% capitalizeFirstLetter - Function
%
% function newStr = capitalizeFirstLetter(str)
%
% This function returns a new string with the first letter of each word capitalized.
%
% Parameters:
%   str: The input string.


function newStr = capitalizeFirstLetter(str)
    arguments
        str {mustBeTextScalar}
    end

    % Split the string into words
    words = strsplit(str, ' ');

    % Capitalize the first letter of each word
    for i = 1:numel(words)
        words{i} = upper(words{i}(1)) + words{i}(2:end);
    end

    % Concatenate the words back into a single string
    newStr = strjoin(words, ' ');
end