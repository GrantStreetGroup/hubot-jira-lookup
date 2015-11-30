# Description:
#   Jira lookup when issues are heard
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_JIRA_LOOKUP_USERNAME
#   HUBOT_JIRA_LOOKUP_PASSWORD
#   HUBOT_JIRA_LOOKUP_URL
#   HUBOT_JIRA_LOOKUP_IGNORE_USERS (optional, format: "user1|user2", default is "jira|github")
#   HUBOT_JIRA_LOOKUP_INC_DESC
#   HUBOT_JIRA_LOOKUP_MAX_DESC_LEN
#   HUBOT_JIRA_LOOKUP_SIMPLE
#   HUBOI_JIRA_LOOKUP_TIMEOUT
#
# Commands:
#   None
#
# Author:
#   Matthew Finlayson <matthew.finlayson@jivesoftware.com> (http://www.jivesoftware.com)
#   Benjamin Sherman  <benjamin@jivesoftware.com> (http://www.jivesoftware.com)
#   Dustin Miller <dustin@sharepointexperts.com> (http://sharepointexperience.com)


## Prevent the bot sending the jira ticket details too often in any channel

## Store when a ticket was reported to a channel
# Key:   channelid-ticketid
# Value: timestamp
# 
LastHeard = {}

RecordLastHeard = (robot,channel,ticket) ->
  ts = new Date()
  key = "#{channel}-#{ticket}"
  LastHeard[key] = ts

CheckLastHeard = (robot,channel,ticket) ->
  now = new Date()
  key = "#{channel}-#{ticket}"
  last = LastHeard[key] || 0
  timeout =  process.env.HUBOT_JIRA_LOOKUP_TIMEOUT || 15
  limit = (1000 * 60 * timeout)
  diff = now - last

  @robot.logger.debug "Check: #{key} #{diff} #{limit}"
  
  if diff < limit
    return yes
  no

module.exports = (robot) ->

  ignored_users = process.env.HUBOT_JIRA_LOOKUP_IGNORE_USERS
  if ignored_users == undefined
    ignored_users = "jira|github"

  console.log "Ignore Users: #{ignored_users}"

  robot.hear /\b([a-zA-Z]{2,12}-[0-9]{1,10})[a-z]?\b/, (msg) ->

    return if msg.message.user.name.match(new RegExp(ignored_users, "gi"))

    issue = msg.match[1]
    room  = msg.message.user.reply_to || msg.message.user.room
    
    @robot.logger.debug "Issue: #{issue} in channel #{room}"

    return if CheckLastHeard(robot, room, issue)

    RecordLastHeard robot, room, issue

    if process.env.HUBOT_JIRA_LOOKUP_SIMPLE is "true"
      msg.send "Issue: #{issue} - #{process.env.HUBOT_JIRA_LOOKUP_URL}/browse/#{issue}"
    else
      user = process.env.HUBOT_JIRA_LOOKUP_USERNAME
      pass = process.env.HUBOT_JIRA_LOOKUP_PASSWORD
      url = process.env.HUBOT_JIRA_LOOKUP_URL

      inc_desc = process.env.HUBOT_JIRA_LOOKUP_INC_DESC
      if inc_desc == undefined
         inc_desc = "Y"

      max_len = process.env.HUBOT_JIRA_LOOKUP_MAX_DESC_LEN

      auth = 'Basic ' + new Buffer(user + ':' + pass).toString('base64')

      robot.http("#{url}/rest/api/latest/issue/#{issue}")
        .headers(Authorization: auth, Accept: 'application/json')
        .get() (err, res, body) ->
          try
            json = JSON.parse(body)

            data = {
              'key': {
                key: 'Key'
                value: issue
              }
              'summary': {
                key: 'Summary'
                value: json.fields.summary || null
              }
              'link': {
                key: 'Link'
                value: "#{process.env.HUBOT_JIRA_LOOKUP_URL}/browse/#{json.key}"
              }
              'description': {
                key: 'Description',
                value: json.fields.description || null
              }
              'assignee': {
                key: 'Assignee',
                value: (json.fields.assignee && json.fields.assignee.displayName) || 'Unassigned'
              }
              'reporter': {
                key: 'Reporter',
                value: (json.fields.reporter && json.fields.reporter.displayName) || null
              }
              'created': {
                key: 'Created',
                value: json.fields.created && (new Date(json.fields.created)).toLocaleString() || null
              }
              'status': {
                key: 'Status',
                value: (json.fields.status && json.fields.status.name) || null
              }
              'county': {
                key: 'County',
                value: (json.fields.customfield_12424 && json.fields.customfield_12424
                       .map (item) ->
                            item.value
                       .join (", ") 
                       ) || "n/a"
              }
            }

            # Single Line Summary
            fallback = "#{data.key.value}: #{data.summary.value} [#{data.status.value}; assigned to #{data.assignee.value}; county #{data.county.value};] #{data.link.value}" 

            if process.env.HUBOT_SLACK_INCOMING_WEBHOOK? 
              robot.emit 'slack.attachment',
                message: msg.message
                content:
                  fallback: fallback
                  title: "#{data.key.value}: #{data.summary.value}"
                  title_link: data.link.value
                  text: data.description.value
                  fields: [
                    {
                      title: data.county.key
                      value: data.county.value
                      short: true
                    }
                    {
                      title: data.reporter.key
                      value: data.reporter.value
                      short: true
                    }
                    {
                      title: data.assignee.key
                      value: data.assignee.value
                      short: true
                    }
                    {
                      title: data.status.key
                      value: data.status.value
                      short: true
                    }
                    {
                      Title: data.created.key
                      value: data.created.value
                      short: true
                    }
                  ]
            else
              msg.send fallback
          catch error
            console.log error
