------------------------------------------------------------------------------
--                                                                          --
--                             GPREXEC                                      --
--                                                                          --
--                   Copyright (C) 2018, Vincent Celier                     --
--                                                                          --
-- This library is free software;  you can redistribute it and/or modify it --
-- under terms of the  GNU General Public License  as published by the Free --
-- Software  Foundation;  either version 3,  or (at your  option) any later --
-- version. This library is distributed in the hope that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE.                            --
------------------------------------------------------------------------------

with GNAT.OS_Lib; use GNAT.OS_Lib;

with GPR;  use GPR;
with GPR.Tree;

package GPRExec is
   Root_Environment : GPR.Tree.Environment;

   Project_Tree : constant Project_Tree_Ref :=
                    new Project_Tree_Data (Is_Root_Tree => True);
   --  The project tree

   Copyright_Output : Boolean := False;
   Usage_Output     : Boolean := False;
   --  Flags to avoid multiple displays of Copyright notice and of Usage

   Project_File_Name_Expected : Boolean := False;
   --  True when last switch was -P

   Goal : String_Access := null;
   --  The name of the goal

   Goal_Id : Name_Id;

   Name_Execution  : Name_Id;
   Name_Dependency : Name_Id;
   Name_Process    : Name_Id;
   Name_Goals      : Name_Id;

   Target_Name : String_Access := null;

   Config_Project_File_Name   : String_Access := null;
   Configuration_Project_Path : String_Access := null;
   --  Base name and full path to the configuration project file

   Execution_String : aliased String := "execution";

   List_Of_Packages : aliased String_List := (1 => Execution_String'Access);
   Packages_To_Check : constant String_List_Access := List_Of_Packages'Access;

   Main_Project : Project_Id;
   --  The project id of the main project

   procedure Process_Package_Execution;

   procedure Register_Package_Execution;
   --  Add package Execution

   function Gprexec_Flags return Processing_Flags;

end GPRExec;
