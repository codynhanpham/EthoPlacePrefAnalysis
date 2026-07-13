function restoreProgressDialogState(progressDialogHandle, indeterminateState, messageText)
    try
        progressDialogHandle.Indeterminate = indeterminateState;
        progressDialogHandle.Message = messageText;
    catch
        % Ignore cleanup errors when the dialog has already been closed.
    end
end