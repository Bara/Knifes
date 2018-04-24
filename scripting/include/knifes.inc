#if defined _knifes_included
 #endinput
#endif
#define _knifes_included

native int Knifes_GetIndex(int client);

public SharedPlugin __pl_knifes = 
{
    name = "knifes",
    file = "knifes.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_knifes_SetNTVOptional()
{
    MarkNativeAsOptional("Knifes_GetIndex");
}
#endif
