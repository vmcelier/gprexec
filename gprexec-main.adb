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

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;   use Ada.Exceptions;
with Ada.Text_IO;      use Ada.Text_IO;

with GNAT.OS_Lib;                use GNAT.OS_Lib;

with GPR;                        use GPR;
with GPR.Conf;                   use GPR.Conf;
with GPR.Names;                  use GPR.Names;
with GPR.Opt;                    use GPR.Opt;
with GPR.Osint;                  use GPR.Osint;
with GPR.Env;
with GPR.Err;
with GPR.Snames;                 use GPR.Snames;
with GPR.Tree;                   use GPR.Tree;
with GPR.Util;                   use GPR.Util;

procedure GPRExec.Main is

   Current_Year : constant String := "2018";

   Saved_Verbosity : Verbosity := Default;

   User_Project_Node : Project_Node_Id;

   procedure Copyright;
   --  Output the Copyright notice

   procedure Initialize;
   --  Do the necessary package intialization and process the command line
   --  arguments.

   procedure Scan_Arg (Arg : String; Success : out Boolean);

   procedure Usage;
   --  Display the usage

   ---------------
   -- Copyright --
   ---------------

   procedure Copyright is
      Version_String : constant String := "0.1";
      Initial_Year   : constant String := "2018";
   begin
      --  Only output the Copyright notice once

      if not Copyright_Output then
         Copyright_Output := True;
         Put_Line ("GPREXEC " & Version_String);
         Put ("Copyright (C) " & Initial_Year);

         if Current_Year > Initial_Year then
            Put ("-" & Current_Year);
         end if;

         Put (" Vincent Celier");
         New_Line;
      end if;
   end Copyright;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize is
      procedure Check_Version_And_Help is new
        Check_Version_And_Help_G (Usage);
   begin
      Snames.Initialize;

      --  Add names for package execution

      Name_Len := 0;
      Add_Str_To_Name_Buffer ("execution");
      Name_Execution := Name_Find;

      Name_Len := 0;
      Add_Str_To_Name_Buffer ("dependency");
      Name_Dependency := Name_Find;

      Name_Len := 0;
      Add_Str_To_Name_Buffer ("process");
      Name_Process := Name_Find;

      Name_Len := 0;
      Add_Str_To_Name_Buffer ("goals");
      Name_Goals := Name_Find;

      if Argument_Count = 0 then
         Copyright;
         Usage;
         OS_Exit (0);
      end if;

      --  Do some necessary package initializations

      Set_Program_Name ("gprexec");

      GPR.Tree.Initialize (Root_Environment, Gprexec_Flags);
      GPR.Tree.Initialize (Project_Node_Tree);

      Set_Default_Verbosity;

      GPR.Initialize (Project_Tree);

      Register_Package_Execution;

      --  Get the command line arguments, starting with --version and --help

      Check_Version_And_Help
        ("GPREXEC",
         "2018",
         Version_String => "0.1");

      --  Check for switch -h an, if found, display usage and exit

      for Arg in 1 .. Argument_Count loop
         if Argument (Arg) = "-h" then
            Copyright;
            Usage;
            OS_Exit (0);
         end if;
      end loop;

      --  Now process the other options

      Get_Command_Line_Arguments;

      declare
         Do_Not_Care : Boolean;

      begin
         Scan_Args : for Next_Arg in 1 .. Last_Command_Line_Argument loop
            Scan_Arg
              (Command_Line_Argument (Next_Arg),
               Success      => Do_Not_Care);
         end loop Scan_Args;
      end;

      --  Fail if command line ended with "-P"

      if Project_File_Name_Expected then
         Fail_Program
           (Project_Tree, "project file name missing after -P");

      elsif Project_File_Name = null then
         Fail_Program
           (Project_Tree, "no project file name specified");
      end if;

      GPR.Env.Initialize_Default_Project_Path
        (Root_Environment.Project_Path, Target_Name => "-");

      if Goal = null then
         Goal := new String'("default");
      end if;

      Name_Len := 0;
      Add_Str_To_Name_Buffer (Goal.all);
      Goal_Id := Name_Find;

   end Initialize;

   --------------
   -- Scan_Arg --
   --------------

   procedure Scan_Arg (Arg : String; Success : out Boolean) is
   begin
      pragma Assert (Arg'First = 1);

      Success := True;

      if Arg'Length = 0 then
         return;
      end if;

      --  If preceding switch was -P, a project file name need to be
      --  specified, not a switch.

      if Project_File_Name_Expected then
         if Arg (1) = '-' then
            Fail_Program
              (Project_Tree, "project file name missing after -P");
         else
            Project_File_Name_Expected := False;
            Project_File_Name := new String'(Arg);
         end if;

      elsif Arg (1) = '-' then
         if Arg'Length >= 2 and then Arg (2) = 'P' then
            if Project_File_Name /= null then
               Fail_Program
                 (Project_Tree,
                  "cannot have several project files specified");

            elsif Arg'Length = 2 then
               Project_File_Name_Expected := True;

            else
               Project_File_Name := new String'(Arg (3 .. Arg'Last));
            end if;

         elsif Arg = "-v" or else Arg = "-vh" then
            Verbose_Mode    := True;
            Verbosity_Level := Opt.High;
            Quiet_Output    := False;

         elsif Arg = "-vm" then
            Verbose_Mode    := True;
            Verbosity_Level := Opt.Medium;
            Quiet_Output    := False;

         elsif Arg = "-vl" then
            Verbose_Mode    := True;
            Verbosity_Level := Opt.Low;
            Quiet_Output    := False;

         elsif Arg = "-q" then
            Quiet_Output := True;
            Verbose_Mode := False;

         elsif Arg = "-vP0" then
            Saved_Verbosity := GPR.Default;

         elsif Arg = "-vP1" then
            Saved_Verbosity := GPR.Medium;

         elsif Arg = "-vP2" then
            Saved_Verbosity := GPR.High;

         else
            Fail_Program (Project_Tree, "invalid switch """ & Arg & '"');
         end if;

      else
         --  The name of the goal or the file name of the project file

         declare
            File_Name : String := Arg;

         begin
            Canonical_Case_File_Name (File_Name);

            if File_Name'Length > Project_File_Extension'Length
              and then File_Name
                (File_Name'Last - Project_File_Extension'Length + 1
                 .. File_Name'Last) = Project_File_Extension
            then
               if Project_File_Name /= null then
                  Fail_Program
                    (Project_Tree,
                     "cannot have several project files specified");

               else
                  Project_File_Name := new String'(File_Name);
               end if;

            else
               --  Not a project file, then it is the goal

               if Goal /= null then
                  Fail_Program
                    (Project_Tree,
                     "cannot have several goals specified");

               else
                  Goal := new String'(File_Name);
               end if;
            end if;
         end;

      end if;

   end Scan_Arg;
   -----------
   -- Usage --
   -----------

   procedure Usage is
   begin
      if not Usage_Output then
         Usage_Output := True;

         New_Line;

         Put ("Usage: ");
         Put ("gprexec [-P<proj>] [<proj>.gpr] [opts] [name]");
         New_Line;         New_Line;
         New_Line;
         Put ("  name is zero or more goals");
         New_Line;
         New_Line;

         --  GPREXEC switches

         Put ("gprexec switches:");
         New_Line;

         Display_Usage_Version_And_Help;

         New_Line;

         Put_Line ("  -vPx     Specify verbosity when parsing Project Files");
         Put_Line ("  -vx      Specify verbosity when processing goals");
         Put_Line ("  -q       Quiet output when processing goals");
         Put_Line ("  -h       Display version and usage, then exit");

         New_Line;

      end if;
   end Usage;

begin
   Initialize;

   if Target_Name = null then
      Target_Name := new String'("");
   end if;

   if Config_Project_File_Name = null then
      Config_Project_File_Name := new String'("");
   end if;

   Current_Verbosity := Saved_Verbosity;

   begin
      Main_Project := No_Project;
      Parse_Project_And_Apply_Config
        (Main_Project               => Main_Project,
         User_Project_Node          => User_Project_Node,
         Config_File_Name           => Config_Project_File_Name.all,
         Autoconf_Specified         => False,
         Project_File_Name          => Project_File_Name.all,
         Project_Tree               => Project_Tree,
         Project_Node_Tree          => Project_Node_Tree,
         Packages_To_Check          => Packages_To_Check,
         Env                        => Root_Environment,
         Allow_Automatic_Generation => Autoconfiguration,
         Automatically_Generated    => Delete_Autoconf_File,
         Config_File_Path           => Configuration_Project_Path,
         Target_Name                => Target_Name.all,
         Normalized_Hostname        => Knowledge.Normalized_Hostname,
         Implicit_Project           => False);

      --  Print warnings that might have occurred while parsing the project
      GPR.Err.Finalize;

      --  But avoid duplicate warnings later on
      GPR.Err.Initialize;

   exception
      when E : GPR.Conf.Invalid_Config =>
         Fail_Program (Project_Tree, Exception_Message (E));
   end;

   if Main_Project = No_Project then
      --  Don't flush messages in case of parsing error. This has already
      --  been taken care when parsing the tree. Otherwise, it results in
      --  the same message being displayed twice.

      Fail_Program
        (Project_Tree,
         """" & Project_File_Name.all & """ processing failed",
         Flush_Messages => User_Project_Node /= Empty_Project_Node);
   end if;

   --  The current working directory is the project directory

   Ada.Directories.Set_Directory
     (Get_Name_String (Main_Project.Directory.Name));

   Current_Verbosity := Saved_Verbosity;

   Process_Package_Execution;

end GPRExec.Main;
