//
// Copyright (c) Microsoft. All rights reserved.
// Licensed under the MIT license. See LICENSE file in the project root for full license information.
//

using System;
using System.IO;
using System.Management.Automation;
using System.Text;
using Microsoft.PowerShell.Commands;

namespace Microsoft.Azure.Functions.PowerShellWorker.Utility
{
    internal class Utils
    {
        internal static CmdletInfo ImportModuleCmdletInfo = new CmdletInfo("Import-Module", typeof(ImportModuleCommand));
        internal static CmdletInfo RemoveModuleCmdletInfo = new CmdletInfo("Remove-Module", typeof(RemoveModuleCommand));
        internal static CmdletInfo GetJobCmdletInfo = new CmdletInfo("Get-Job", typeof(GetJobCommand));
        internal static CmdletInfo RemoveJobCmdletInfo = new CmdletInfo("Remove-Job", typeof(RemoveJobCommand));

        /// <summary>
        /// Helper method to do additional transformation on the input value based on the type constraints specified in the script.
        /// </summary>
        internal static object TransformInBindingValueAsNeeded(PSScriptParamInfo paramInfo, ReadOnlyBindingInfo bindingInfo, object value)
        {
            switch (bindingInfo.Type)
            {
                case "blob":
                case "blobTrigger":
                    // For blob input, the input data could be an array of bytes or a string. Documentation says
                    // that a user can specify the 'dataType' to make the input data of the expected type. (see
                    // https://docs.microsoft.com/en-us/azure/azure-functions/functions-triggers-bindings#binding-datatype-property)
                    //
                    // However, I found this setting is somewhat broken:
                    //  1. For the 'blobTrigger' type in-binding, the input data is always byte array and the host doesn't
                    //     respect the "dataType" setting in 'function.json'.
                    //  2. For the 'blob' type in-binding, the input data type is 'String' by default. When specified, the
                    //    'binary' and 'string' dataType are respected, but 'stream' dataType is not respected.
                    //
                    // Due to (1), we should be reasonably smart and transform the data appropriately when type constraint is
                    // specified on the input parameter to indicate the expected data type.
                    Type paramType = paramInfo.ParamType;
                    if (value is byte[] blobBytes)
                    {
                        if (paramType == typeof(string))
                        {
                            // String is expected, so convert the byte array to string using UTF8 encoding.
                            // This is a best effort attempt, as we don't know the true encoding.
                            value = Encoding.UTF8.GetString(blobBytes);
                        }
                        else if (paramType == typeof(Stream))
                        {
                            // Stream is expected, so convert the byte array to a MemoryStream.
                            value = new MemoryStream(blobBytes);
                        }
                    }

                    // When the input is 'String', we don't attempt to convert it to bytes because if the blob
                    // is in fact a binary file, it's impossible to get the right bytes back even if we use the
                    // same encoding used by the host when converting those bytes to string.

                    break;
                default:
                    break;
            }

            return value;
        }

        /// <summary>
        /// Helper method to do additional transformation on the output value.
        /// </summary>
        internal static object TransformOutBindingValueAsNeeded(string bindingName, ReadOnlyBindingInfo bindingInfo, object value)
        {
            switch (bindingInfo.Type)
            {
                case "http":
                    // Try converting the value to HttpResponseContext if it's not already an object of such type.
                    if (value is HttpResponseContext)
                    {
                        break;
                    }

                    try
                    {
                        value = LanguagePrimitives.ConvertTo<HttpResponseContext>(value);
                    }
                    catch (PSInvalidCastException ex)
                    {
                        string errorMsg = string.Format(PowerShellWorkerStrings.FailToConvertToHttpResponseContext, bindingName, ex.Message);
                        throw new InvalidOperationException(errorMsg);
                    }

                    break;
                default:
                    break;
            }

            return value;
        }
    }
}
