import * as vscode from "vscode";
import { createExtension } from "./extension-host.mjs";

const extension = createExtension(vscode);
export const activate = extension.activate;
export const deactivate = extension.deactivate;
