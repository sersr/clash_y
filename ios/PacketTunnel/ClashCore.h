#ifndef CLASHY_CLASH_CORE_H
#define CLASHY_CLASH_CORE_H

char *prepare(char *configDir);
char *startTun(char *configDir, int fd);
char *refreshProfile(char *configDir, char *url, char *script);
char *stop(void);
void freeString(char *message);

#endif
